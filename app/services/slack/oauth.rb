# frozen_string_literal: true

module Slack
  # Helpers for the Slack OAuth v2 install flow. The redirect URI is a single,
  # deployment-wide callback registered on the Slack app; the project + initiating
  # user are carried in a signed, short-lived, SINGLE-USE `state` so the callback
  # can (a) bind the install to the right project, (b) confirm the same user is
  # completing the flow (anti-CSRF), and (c) reject replays.
  module Oauth
    AUTHORIZE_URL = "https://slack.com/oauth/v2/authorize"
    STATE_TTL = 10.minutes

    class << self
      def authorize_url(project:, user:)
        query = URI.encode_www_form(
          client_id: Settings.slack.client_id,
          scope: bot_scopes,
          redirect_uri: redirect_uri,
          state: sign_state(project, user)
        )
        "#{AUTHORIZE_URL}?#{query}"
      end

      def redirect_uri
        "#{Settings.protocol}://#{Settings.domain}/integrations/slack/oauth/callback"
      end

      # Signs {project_id, user_id, nonce}. The nonce is recorded in the cache so
      # the callback can enforce single use (consume_state_nonce).
      def sign_state(project, user)
        nonce = SecureRandom.uuid
        Rails.cache.write(nonce_key(nonce), true, expires_in: STATE_TTL)
        verifier.generate(
          { "project_id" => project.id, "user_id" => user.id, "nonce" => nonce },
          expires_in: STATE_TTL, purpose: :slack_oauth
        )
      end

      # Returns the decoded state hash, or nil if tampered/expired.
      def verify_state(state)
        verifier.verify(state.to_s, purpose: :slack_oauth)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      # Consume the one-time nonce: true the first time, false on replay/expiry.
      def consume_state_nonce(nonce)
        return false if nonce.blank?

        Rails.cache.delete(nonce_key(nonce))
      end

      private

      def nonce_key(nonce)
        "slack_oauth_state:#{nonce}"
      end

      # Slack expects comma-separated bot scopes; tolerate spaces in the setting.
      def bot_scopes
        Settings.slack.scopes.to_s.split(/[,\s]+/).reject(&:blank?).join(",")
      end

      def verifier
        Rails.application.message_verifier("slack_oauth")
      end
    end
  end
end
