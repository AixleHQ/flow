# frozen_string_literal: true

module Github
  class RepositoryService
    def initialize(integration)
      @integration = integration
    end

    # What this connection can attach.
    #
    # The two modes ask GitHub different questions, because they are different
    # kinds of credential: an installation covers the repositories an App was
    # granted, a personal access token covers the repositories its owner can
    # reach. `/installation/repositories` answers only the first and refuses a
    # token with 403 "Resource not accessible by personal access token", so PAT
    # mode asks `/user/repos` instead.
    def list_available
      repos =
        if pat_mode?
          client(auto_paginate: true).repos(
            nil, affiliation: "owner,collaborator,organization_member", per_page: 100
          )
        else
          client(auto_paginate: true).list_app_installation_repositories[:repositories]
        end

      repos.map { |repo| map_repo(repo) }
    rescue Octokit::Error => e
      Rails.logger.warn("[Github::RepositoryService] Failed to list repos: #{e.message}")
      []
    end

    def find_repo(full_name)
      map_repo(client.repository(full_name))
    rescue Octokit::Error => e
      Rails.logger.warn("[Github::RepositoryService] Failed to find repo #{full_name}: #{e.message}")
      nil
    end

    def list_branches(full_name)
      client(auto_paginate: true).branches(full_name).map(&:name)
    rescue Octokit::Error => e
      Rails.logger.warn("[Github::RepositoryService] Failed to list branches for #{full_name}: #{e.message}")
      []
    end

    def configure(repository)
      # GitHub uses App installation webhooks — no per-repository setup needed.
      # A PAT connection registers no webhook of its own either: a local
      # deployment is usually unreachable from github.com, so a hook would fail
      # to create or silently never deliver. CI gates on a PAT connection
      # resolve through GateReconciler's polling instead of an event.
    end

    def remove(repository)
      # GitHub uses App installation webhooks — no per-repository cleanup needed
    end

    private

    def pat_mode?
      @integration.github_pat?
    end

    def client(auto_paginate: false)
      token = Github::TokenService.new(@integration).generate_installation_token
      client = Octokit::Client.new(access_token: token)
      client.auto_paginate = auto_paginate
      client
    end

    def map_repo(repo)
      {
        full_name: repo.full_name,
        default_branch: repo.default_branch || "main",
        clone_url: repo.clone_url,
        is_private: repo.private,
        description: repo.description
      }
    end
  end
end
