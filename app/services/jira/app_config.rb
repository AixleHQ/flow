# frozen_string_literal: true

module Jira
  module AppConfig
    API_HOST = "https://api.atlassian.com"
    AUTH_HOST = "https://auth.atlassian.com"

    module_function

    def client_id = Settings.jira&.client_id.to_s.presence
    def client_secret = Settings.jira&.client_secret.to_s.presence
    def oauth_enabled? = client_id.present? && client_secret.present?

    def open_timeout = 5
    def read_timeout = 20

    def webhook_base_url
      Settings.jira&.webhook_base_url.presence || "#{Settings.protocol}://#{Settings.domain}"
    end

    # Atlassian accepts a webhook to a host it cannot reach and then fails every
    # delivery in silence, so a loopback or private host registers none.
    def webhooks_enabled?
      host = URI.parse(webhook_base_url.to_s).host.to_s
      return false unless host.include?(".")
      return false if host.end_with?(".local", ".internal", ".localdomain")

      !host.match?(/\A(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/)
    rescue URI::InvalidURIError
      false
    end
  end
end
