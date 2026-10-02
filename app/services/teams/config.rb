# frozen_string_literal: true

module Teams
  # The deployment's bot: which Entra app it is, how it proves that, and which
  # Microsoft cloud it talks to.
  module Config
    # Hosts an activity's serviceUrl may name; a reply is only ever sent to one
    # of them, whatever an activity claims.
    CLOUDS = {
      "public" => {
        login: "https://login.microsoftonline.com",
        bot_scope: "https://api.botframework.com/.default",
        issuer: "https://api.botframework.com",
        openid: "https://login.botframework.com/v1/.well-known/openidconfiguration",
        graph: "https://graph.microsoft.com",
        service_hosts: %w[smba.trafficmanager.net]
      }
    }.freeze

    GUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    module_function

    def app_id = teams(:app_id) || microsoft(:client_id)
    def private_key = teams(:private_key) || microsoft(:private_key)
    def certificate_thumbprint = teams(:certificate_thumbprint) || microsoft(:certificate_thumbprint)
    def client_secret = teams(:client_secret)
    def home_tenant_id = teams(:home_tenant_id)

    def certificate?
      private_key.present? && certificate_thumbprint.present?
    end

    # Offered exactly when a bot can authenticate: an app, a credential, and the
    # home tenant its Azure Bot was registered in.
    def enabled?
      app_id.present? && home_tenant_id.to_s.match?(GUID) && (certificate? || client_secret.present?)
    end

    def cloud
      CLOUDS.fetch(teams(:cloud) || "public")
    end

    def service_url_allowed?(url)
      uri = URI.parse(url.to_s)
      uri.scheme == "https" && cloud[:service_hosts].include?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def teams(key) = Settings.teams&.public_send(key).presence
    def microsoft(key) = Settings.microsoft_oauth&.public_send(key).presence
  end
end
