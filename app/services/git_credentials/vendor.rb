# frozen_string_literal: true

module GitCredentials
  # A short-lived credential for one GitHub or GitLab repository attached to a
  # session: an installation token narrowed to that repository for a GitHub App
  # connection, the stored token for a personal-access-token connection (which
  # cannot be narrowed — see docs/user-guide/integrations.md).
  class Vendor
    PROVIDERS = %w[github gitlab].freeze

    Credential = Data.define(:username, :password)
    NotAuthorized = Class.new(StandardError)

    def self.clone_url(repository)
      case repository.integration&.provider.to_s
      when "github" then "https://github.com/#{repository.full_name}.git"
      when "gitlab" then "#{Gitlab::Host.web_base}/#{repository.full_name}.git"
      end
    end

    def initialize(session)
      @session = session
    end

    # `requested_url` is what git is talking to; it has to be the repository's own.
    def vend!(repository_id:, requested_url: nil)
      repository = @session.repositories.includes(:integration).find_by(id: repository_id)
      raise NotAuthorized, "repository is not attached to this session" unless vendable?(repository)
      raise NotAuthorized, "url is not this repository's" if requested_url.present? && !same_repository?(repository, requested_url)

      token = token_for(repository)
      raise NotAuthorized, "no credential available" if token.blank?

      Credential.new(username: repository.integration.github? ? "x-access-token" : "oauth2", password: token)
    end

    private

    def vendable?(repository)
      repository&.integration&.active? && PROVIDERS.include?(repository.integration.provider.to_s)
    end

    def token_for(repository)
      integration = repository.integration
      if integration.github?
        Github::TokenService.new(integration).generate_installation_token(repositories: [ repository.repo_name ])
      else
        integration.credentials_data["personal_access_token"]
      end
    end

    def same_repository?(repository, url)
      expected = URI.parse(self.class.clone_url(repository).to_s)
      given = URI.parse(url.to_s)
      given.host.to_s.casecmp?(expected.host.to_s) && repo_path(given) == repo_path(expected)
    rescue URI::InvalidURIError
      false
    end

    def repo_path(uri)
      uri.path.to_s.delete_prefix("/").delete_suffix("/").delete_suffix(".git").downcase
    end
  end
end
