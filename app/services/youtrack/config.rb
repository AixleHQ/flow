# frozen_string_literal: true

module Youtrack
  module Config
    # The Aixle Flow app on JetBrains Marketplace (youtrack-app/), and its
    # admin page that approves a pairing Aixle started.
    APP_NAME = "aixle-flow"
    CONNECT_PAGE = "connect"
    MARKETPLACE_URL = "https://plugins.jetbrains.com/search?search=Aixle%20Flow"

    module_function

    def open_timeout = 5
    def read_timeout = 20

    # A self-hosted instance on a private network is reachable only when the
    # operator names its host; a customer cannot aim Aixle at one.
    def trusted_hosts
      Settings.youtrack&.trusted_hosts.to_s.split(/[\s,]+/).compact_blank
    end

    def webhook_base_url
      Settings.youtrack&.webhook_base_url.presence || "#{Settings.protocol}://#{Settings.domain}"
    end

    # The fragment never reaches a server, so the secret stays out of logs.
    # YouTrack hands an app only the parameters prefixed `app_`.
    def connect_url(base_url, pairing_id, secret)
      "#{base_url}/admin/app/#{APP_NAME}/#{CONNECT_PAGE}#app_pairing=#{pairing_id}.#{secret}"
    end

    # The instance URL as Aixle keeps it: https, no trailing slash, no /api, no
    # query — what an issue's browser URL is built on and what identifies the
    # instance. A self-hosted path prefix (/youtrack) stays.
    def normalize_base_url(url)
      uri = URI.parse(url.to_s.strip)
      return if uri.host.blank?

      path = uri.path.to_s.sub(%r{/+\z}, "").sub(%r{/api\z}i, "")
      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme.to_s.downcase}://#{uri.host.downcase}#{port}#{path}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
