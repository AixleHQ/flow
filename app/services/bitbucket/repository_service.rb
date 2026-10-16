# frozen_string_literal: true

module Bitbucket
  # The repository picker's view of one connection's workspace. Same shape as
  # the GitLab and GitHub services, plus the three UUIDs a Bitbucket Repository
  # row is addressed by (docs/design/bitbucket-integration.md §6.4).
  #
  # A credential can reach repositories in other workspaces — an API token is a
  # person, and people belong to several — so every answer is confined to the
  # connection's own workspace.
  class RepositoryService
    MAX_BRANCHES = 1000

    def initialize(integration)
      @integration = integration
    end

    def list_available
      api.repositories(workspace).filter_map { |repo| map_repository(repo) if own?(repo) }
    rescue Error => e
      Rails.logger.warn("[Bitbucket::RepositoryService] Failed to list repositories: #{e.code}")
      []
    end

    def find_repo(ref)
      find_repo!(ref)
    rescue Error => e
      Rails.logger.warn("[Bitbucket::RepositoryService] Failed to find #{ref}: #{e.code}")
      nil
    end

    # `ref` is "workspace/slug", a repository UUID, or a Repository row.
    def find_repo!(ref)
      repo = api.repository(*address(ref))
      raise Error::NotFound, "#{ref} is not in the #{@integration.bitbucket_workspace_slug} workspace" unless own?(repo)

      map_repository(repo)
    end

    def list_branches(ref)
      api.branches(*address(ref), limit: MAX_BRANCHES)
    rescue Error => e
      Rails.logger.warn("[Bitbucket::RepositoryService] Failed to list branches of #{ref}: #{e.code}")
      []
    end

    # CI events reach Aixle through the Forge app, or not at all in token mode:
    # there is no per-repository hook to register or remove.
    def configure(_repository) = nil
    def remove(_repository) = nil

    private

    def api = @api ||= Api.for(@integration)

    def workspace = @integration.bitbucket_workspace_uuid.presence || @integration.bitbucket_workspace_slug

    def address(ref)
      case ref
      when Repository then [ ref.external_organization_id.presence || workspace, ref.external_id.presence || ref.repo_name ]
      else
        text = ref.to_s.strip
        return [ workspace, Identifiers.uuid(text) ] if Identifiers.uuid(text)

        owner, slug = text.split("/", 2)
        raise Error::ValidationFailed, "#{text} is not a workspace/repository name" if owner.blank? || slug.blank? || slug.include?("/")

        [ owner, slug ]
      end
    end

    def own?(repo)
      expected = Identifiers.uuid(@integration.bitbucket_workspace_uuid)
      return repo[:workspace_slug].to_s.casecmp?(@integration.bitbucket_workspace_slug.to_s) if expected.nil?

      repo[:workspace_uuid] == expected
    end

    def map_repository(repo)
      {
        full_name: repo[:full_name],
        default_branch: repo[:default_branch] || "main",
        clone_url: "#{AppConfig::WEB_HOST}/#{repo[:full_name]}.git",
        is_private: repo[:is_private],
        description: repo[:description],
        external_id: repo[:uuid],
        external_organization_id: repo[:workspace_uuid],
        external_project_id: repo[:project_uuid]
      }
    end
  end
end
