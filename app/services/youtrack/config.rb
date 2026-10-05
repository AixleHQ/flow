# frozen_string_literal: true

module Youtrack
  module Config
    DEFAULT_WEBHOOK_HEADER = "X-YouTrack-Token"

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
