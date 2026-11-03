# frozen_string_literal: true

module RunnerGateway
  module V1
    # The runner gateway, `/runner/v1/*` (docs/design/agent-runtimes/DESIGN.md
    # §6): the JSON API `aixle-runner` calls. No cookie session and no CSRF:
    # every request carries `Authorization: Bearer <token>`,
    # `X-Aixle-Runner-Protocol: 1` and `X-Aixle-Runner-Version: <semver>`.
    # It is served by its own Puma (config/puma_runner_gateway.rb) so that held
    # long-polls never take the UI's threads.
    #
    # Every authenticated request re-checks, in this order: the token, the
    # runner's status (revoked or deleted answers 401, cached for at most
    # STATUS_TTL so a revocation lands within seconds) and the external_runners
    # flag for the runner's company (403 runners_disabled, which leaves the
    # credentials valid, §9.3).
    class ApplicationController < ActionController::API
      PROTOCOL_VERSION = "1"
      SEMVER = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/
      STATUS_TTL = 5.seconds

      REFUSAL_STATUS = {
        "invalid_token" => :unauthorized,
        "credential_reuse_detected" => :unauthorized,
        "runner_revoked" => :unauthorized,
        "ephemeral_not_supported" => :unprocessable_entity,
        "invalid_registration" => :unprocessable_entity
      }.freeze

      wrap_parameters false

      before_action :check_protocol

      rescue_from Runners::Credentials::Refused do |refusal|
        refuse(REFUSAL_STATUS.fetch(refusal.reason), refusal.reason, refusal.message)
      end

      private

      # A spent refresh token passes the token check, so that
      # Runners::Credentials.rotate! sees a second use of one.
      def authenticate(kind)
        @credential = if kind == :refresh
          Runners::Credentials.refreshable(bearer_token)
        else
          Runners::Credentials.usable(bearer_token, kind: kind)
        end
        return refuse(:unauthorized, "invalid_token", "The token is unknown, used, revoked or expired.") if @credential.nil?
        return refuse(:unauthorized, "runner_revoked", "The runner is revoked or deleted.") unless runner_live?(@credential.runner_id)

        unless Feature.enabled?(:external_runners, company: @credential.company)
          refuse(:forbidden, "runners_disabled", "External runners are turned off for this company.")
        end
      end

      def runner_live?(runner_id)
        Rails.cache.fetch("runner_gateway/runner_live/#{runner_id}", expires_in: STATUS_TTL) do
          Runner.where(id: runner_id, deleted_at: nil).where.not(status: "revoked").exists?
        end
      end

      def bearer_token
        request.authorization.to_s[/\ABearer (\S+)\z/, 1]
      end

      def runner_version
        request.headers["X-Aixle-Runner-Version"].to_s
      end

      def check_protocol
        protocol = request.headers["X-Aixle-Runner-Protocol"].to_s
        unless protocol == PROTOCOL_VERSION
          return refuse(:bad_request, "unsupported_protocol",
                        "This gateway speaks runner protocol #{PROTOCOL_VERSION}, and the request asked for " \
                        "#{protocol.empty? ? 'none' : protocol.first(16).inspect}. Update aixle-runner.")
        end
        return if runner_version.match?(SEMVER)

        refuse(:bad_request, "invalid_runner_version", "X-Aixle-Runner-Version must be a semantic version.")
      end

      def refuse(status, error, message)
        render json: { error: error, message: message }, status: status
      end

      def render_pair(pair, status: :ok, **extra)
        response.set_header("Cache-Control", "no-store")
        render json: extra.merge(
          access_token: pair.access_token, access_token_expires_at: pair.access_token_expires_at.iso8601,
          refresh_token: pair.refresh_token, refresh_token_expires_at: pair.refresh_token_expires_at.iso8601
        ), status: status
      end
    end
  end
end
