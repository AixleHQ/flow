# frozen_string_literal: true

module Linear
  module AppConfig
    API_HOST = "https://api.linear.app"
    AUTHORIZE_URL = "https://linear.app/oauth/authorize"

    module_function

    def client_id = Settings.linear&.client_id.to_s.presence
    def client_secret = Settings.linear&.client_secret.to_s.presence
    def oauth_enabled? = client_id.present? && client_secret.present?

    # Signs the deliveries of the app's own webhook, for every workspace that installed it.
    def app_webhook_secret = Settings.linear&.webhook_secret.to_s.presence

    def open_timeout = 5
    def read_timeout = 20

    def webhook_base_url
      Settings.linear&.webhook_base_url.presence || "#{Settings.protocol}://#{Settings.domain}"
    end

    def webhooks_enabled? = Trackers.public_webhook_url?(webhook_base_url)
  end
end
