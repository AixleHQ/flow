# frozen_string_literal: true

module Agents
  # Answers a container CLI's OAuth refresh on the vendor's behalf, so that every holder of
  # a credential refreshes under one lock: this row's.
  #
  # On a laptop Claude Code serializes refreshes across processes with a lockfile next to
  # the one shared credentials file, and inside the lock re-reads that file: if another
  # process already refreshed, it uses that result instead of spending the refresh token
  # again. Each container has its own file and its own lock, so when two busy containers
  # cross the token's expiry together both spend the same single-use refresh token, and the
  # one that comes second is logged out mid-run.
  #
  # The in-container proxy (docker/base/logger/refresh_broker.py) sends the request here.
  # A refresh token we still hold is refreshed for real; one we already replaced gets the
  # tokens that replaced it, which is exactly what the CLI's lockfile would have given it.
  # Anything else goes on to the vendor untouched, as does every request when this endpoint
  # cannot be reached.
  class RefreshBroker
    Result = Struct.new(:outcome, :status, :body, keyword_init: true) do
      def serve? = !status.nil?
    end

    # A served token has to outlive the CLI's own refresh margin (5 minutes in 2.1.281) by
    # enough that it does not ask again at once.
    MIN_SERVED_LIFETIME = 10.minutes
    FORCE_REFRESH_MARGIN_MS = 100.years.in_milliseconds

    def initialize(credential, session:)
      @credential = credential
      @session = session
    end

    # @return [Result] serve? false: let the request through to the vendor
    def call(url:, body:, content_type:)
      return passthrough(:not_brokered) unless adapter.refresh_broker_endpoint?(url)

      token = adapter.presented_refresh_token(body, content_type)
      return passthrough(:not_a_refresh) if token.nil?

      AgentCredential.rotating_for_session(session.id) { resolve(token) }
    end

    private

    attr_reader :credential, :session

    def resolve(token)
      credential.reload
      block = adapter.refresh_tokens(credential.config_data).key(token)
      return refresh(block) if block

      block = credential.retired_refresh_token_block(token)
      return passthrough(:unknown_token) if block.nil?

      serve_current(block, outcome: :replaced_token) || refresh(block)
    end

    def refresh(block)
      result = credential.renew!(source: :container, margin_ms: FORCE_REFRESH_MARGIN_MS, blocks: [ block ])
      credential.await_refresh if result[:status] == :busy
      credential.reload

      return rejected(result) if result[:status] == :error && result[:permanent]
      return passthrough(:refresh_failed) if result[:status] == :error

      serve_current(block, outcome: :refreshed) || passthrough(:refresh_failed)
    end

    def serve_current(block, outcome:)
      stored = credential.config_data[block]
      return nil unless stored.is_a?(Hash) && stored["expiresAt"].to_i > (MIN_SERVED_LIFETIME.from_now.to_f * 1000)

      response = adapter.token_response(stored)
      return nil if response.nil?

      log(outcome, block)
      Result.new(outcome: outcome, status: 200, body: response.to_json)
    end

    # The vendor said no to the token we hold. The CLI is told the same, in the vendor's
    # own words, so it reports a dead login rather than retrying a request we refused.
    def rejected(result)
      log(:rejected, nil)
      Result.new(outcome: :rejected, status: 400,
                 body: { error: "invalid_grant", error_description: result[:detail].to_s }.to_json)
    end

    def passthrough(outcome)
      log(outcome, nil) unless outcome == :not_brokered
      Result.new(outcome: outcome)
    end

    def adapter
      credential.adapter
    end

    def log(outcome, block)
      Rails.logger.info("[RefreshBroker] session=#{session.id} credential=#{credential.id} " \
                        "outcome=#{outcome}#{" block=#{block}" if block}")
    end
  end
end
