# frozen_string_literal: true

module Gitlab
  # The deployment's GitLab OAuth app, and where GitLab posts this deployment's events.
  module AppConfig
    WEBHOOK_PATH = "/webhooks/gitlab"
    PRIVATE_ADDRESS = /\A(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/

    module_function

    def oauth_client_id = Settings.gitlab&.oauth_client_id.to_s.presence
    def oauth_client_secret = Settings.gitlab&.oauth_client_secret.to_s.presence
    def oauth_enabled? = oauth_client_id.present? && oauth_client_secret.present?

    def open_timeout = 5
    def read_timeout = 20

    def webhook_base_url
      Settings.gitlab&.webhook_base_url.presence || "#{Settings.protocol}://#{Settings.domain}"
    end

    def webhook_url
      "#{webhook_base_url.chomp('/')}#{WEBHOOK_PATH}"
    end

    # A hook GitLab cannot deliver to is no hook at all, so none is registered for
    # a loopback or private host. The exception is a self-managed GitLab that is
    # itself on a private host: it shares the network, and may reach ours.
    def webhooks_enabled?
      host = host_of(webhook_base_url)
      return false if host.blank? || loopback?(host)

      public_host?(host) || !public_host?(host_of(Host.api_endpoint))
    end

    def log_unreachable_once
      return if @unreachable_logged

      @unreachable_logged = true
      Rails.logger.warn("[Gitlab::AppConfig] GitLab cannot reach #{webhook_url}, so no pipeline hook is registered " \
                        "and GitLab gates resolve on the reconciliation sweep. Set GITLAB_WEBHOOK_BASE_URL to a " \
                        "host GitLab can reach.")
    end

    def host_of(url)
      URI.parse(url.to_s).hostname.to_s.downcase
    rescue URI::InvalidURIError
      ""
    end

    def loopback?(host)
      host == "localhost" || host.end_with?(".localhost") || host.start_with?("127.") || host.in?(%w[::1 0.0.0.0])
    end

    def public_host?(host)
      return false unless host.include?(".")
      return false if host.end_with?(".local", ".internal", ".localdomain")

      !host.match?(PRIVATE_ADDRESS)
    end
  end
end
