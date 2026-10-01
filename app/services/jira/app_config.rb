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

    def webhooks_enabled? = Trackers.public_webhook_url?(webhook_base_url)
  end
end
