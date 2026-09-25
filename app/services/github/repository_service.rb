# frozen_string_literal: true

module Github
  class RepositoryService
    # Listings are walked a page (100 rows) at a time up to this many pages: the
    # whole listing for any real account, but never an unbounded walk inside a
    # web request — Octokit's own auto_paginate has no limit.
    MAX_PAGES = 10

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
          paged { |c| c.repos(nil, affiliation: "owner,collaborator,organization_member", per_page: 100) }
        else
          paged(within: :repositories) { |c| c.list_app_installation_repositories(per_page: 100) }
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
      paged { |c| c.branches(full_name, per_page: 100) }.map(&:name)
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

    def client
      Octokit::Client.new(access_token: Github::TokenService.new(@integration).generate_installation_token)
    end

    # The first page comes from the block; later ones follow the Link header.
    # `within` names the key that holds the rows when a page wraps them.
    def paged(within: nil)
      github = client
      rows = rows_of(yield(github), within)
      response = github.last_response
      (MAX_PAGES - 1).times do
        link = response&.rels&.[](:next)
        break unless link

        response = link.get
        rows.concat(rows_of(response.data, within))
      end
      rows
    end

    def rows_of(page, within)
      Array(within ? page[within] : page)
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
