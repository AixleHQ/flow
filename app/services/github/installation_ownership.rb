# frozen_string_literal: true

module Github
  # Proves that the person completing a GitHub App install can see the
  # installation, through GitHub's user-to-server OAuth ("Request user
  # authorization (OAuth) during installation" on the App): the setup redirect
  # then carries a `code`, which is exchanged for that user's token, and
  # `GET /user/installations` has to list the installation.
  #
  # Enforced once the deployment configures the App's client id and secret.
  # Without them the one-installation-per-company claim on Integration is the
  # only guard, and an installation nobody has connected yet can be connected
  # by whoever forges the setup callback first.
  class InstallationOwnership
    def self.enforced?
      Settings.github.client_id.present? && Settings.github.client_secret.present?
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
