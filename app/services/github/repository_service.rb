# frozen_string_literal: true

module Github
  class RepositoryService
    def initialize(integration)
      @integration = integration
    end

    def list_available
      token = Github::TokenService.new(@integration).generate_installation_token
      client = Octokit::Client.new(access_token: token)
      client.auto_paginate = true

      repos = client.list_app_installation_repositories[:repositories]
      repos.map do |repo|
        {
          full_name: repo.full_name,
          default_branch: repo.default_branch || "main",
          clone_url: repo.clone_url,
          is_private: repo.private,
          description: repo.description
        }
      end
    rescue Octokit::Error => e
      Rails.logger.warn("[Github::RepositoryService] Failed to list repos: #{e.message}")
      []
    end

    def find_repo(full_name)
      token = Github::TokenService.new(@integration).generate_installation_token
      client = Octokit::Client.new(access_token: token)

      repo = client.repository(full_name)
      {
        full_name: repo.full_name,
        default_branch: repo.default_branch || "main",
        clone_url: repo.clone_url,
        is_private: repo.private,
        description: repo.description
      }
    rescue Octokit::Error => e
      Rails.logger.warn("[Github::RepositoryService] Failed to find repo #{full_name}: #{e.message}")
      nil
    end

    def list_branches(full_name)
      token = Github::TokenService.new(@integration).generate_installation_token
      client = Octokit::Client.new(access_token: token)
      client.auto_paginate = true

      client.branches(full_name).map(&:name)
    rescue Octokit::Error => e
      Rails.logger.warn("[Github::RepositoryService] Failed to list branches for #{full_name}: #{e.message}")
      []
    end

    def configure_webhook(repository)
      # GitHub uses App installation webhooks — no per-repository setup needed
    end
  end
end
