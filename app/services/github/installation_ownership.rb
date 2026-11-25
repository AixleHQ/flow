# frozen_string_literal: true

module Github
  # Proves that the person connecting a GitHub App installation can see it,
  # through GitHub's user-to-server OAuth: their `code` is exchanged for their
  # token, and `GET /user/installations` has to list the installation.
  #
  # GitHub puts a code on the setup redirect only for a new installation with
  # "Request user authorization (OAuth) during installation" on. An update of an
  # installation that already exists (Configure → Save on GitHub) never carries
  # one, so GithubSetupController sends a person who arrives without a code
  # through .authorize_url, which comes back with one.
  #
  # Enforced once the deployment sets GITHUB_APP_VERIFY_INSTALLATION_OWNER and configures
  # the App's client id and secret. The client credentials alone only enable
  # connecting a user's own account.
  # Without them the one-installation-per-company claim on Integration is the
  # only guard, and an installation nobody has connected yet can be connected
  # by whoever forges the setup callback first.
  class InstallationOwnership
    AUTHORIZE_URL = "https://github.com/login/oauth/authorize"

    def self.enforced?
      Settings.github.verify_installation_owner == true && Settings.github.client_id.present? && Settings.github.client_secret.present?
    end

    # `redirect_uri` has to be one of the App's registered Redirect URIs.
    def self.authorize_url(redirect_uri:, state:)
      "#{AUTHORIZE_URL}?#{URI.encode_www_form(client_id: Settings.github.client_id, redirect_uri: redirect_uri, state: state)}"
    end

    def initialize(code:)
      @code = code.to_s
    end

    def includes?(installation_id)
      return false if @code.blank?

      token = Octokit.exchange_code_for_token(@code, Settings.github.client_id, Settings.github.client_secret)
      access_token = token.respond_to?(:access_token) ? token.access_token : token[:access_token]
      return false if access_token.blank?

      installations = Octokit::Client.new(access_token: access_token).find_user_installations(per_page: 100)
      Array(installations[:installations]).any? { |installation| installation[:id].to_i == installation_id.to_i }
    rescue Octokit::Error, Faraday::Error => e
      Rails.logger.warn("[Github::InstallationOwnership] verification failed: #{e.class}")
      false
    end
  end
end
