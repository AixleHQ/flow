# frozen_string_literal: true

module Gitlab
  class RepositoryService
    def initialize(integration)
      @integration = integration
    end

    def list_available
      client = token_service.client
      projects = client.projects(membership: true, per_page: 100, auto_paginate: true)
      projects.map { |proj| map_project(proj) }
    rescue ::Gitlab::Error::Error => e
      Rails.logger.warn("[Gitlab::RepositoryService] Failed to list repos: #{e.message}")
      []
    end

    def find_repo(full_name)
      client = token_service.client
      proj = client.project(full_name)
      map_project(proj)
    rescue ::Gitlab::Error::Error => e
      Rails.logger.warn("[Gitlab::RepositoryService] Failed to find repo #{full_name}: #{e.message}")
      nil
    end

    def list_branches(full_name)
      client = token_service.client
      client.branches(full_name).map(&:name)
    rescue ::Gitlab::Error::Error => e
      Rails.logger.warn("[Gitlab::RepositoryService] Failed to list branches for #{full_name}: #{e.message}")
      []
    end

    # Several repository rows can point the same GitLab project at this
    # deployment (two Flow projects, or two companies), each with its own hook
    # and secret. A row therefore keeps the id of the hook it registered and only
    # ever deletes that one.
    def configure(repository)
      client = token_service.client
      delete_hook(client, repository.full_name, repository.gitlab_hook_id) if repository.gitlab_hook_id

      webhook_secret = SecureRandom.hex(32)
      hook = client.add_project_hook(
        repository.full_name,
        Gitlab::AppConfig.webhook_url,
        token: webhook_secret,
        pipeline_events: true
      )
      repository.update!(webhook_secret: webhook_secret, gitlab_hook_id: hook.id)
      webhook_secret
    end

    def remove(repository)
      return if repository.webhook_secret.blank?

      client = token_service.client
      hook_ids = repository.gitlab_hook_id ? [ repository.gitlab_hook_id ] : unclaimed_hook_ids(client, repository)
      hook_ids.each { |hook_id| delete_hook(client, repository.full_name, hook_id) }
    rescue ::Gitlab::Error::Error => e
      Rails.logger.warn("[Gitlab::RepositoryService] Failed to remove webhook for #{repository.full_name}: #{e.message}")
    end

    private

    def delete_hook(client, full_name, hook_id)
      client.delete_project_hook(full_name, hook_id)
    rescue ::Gitlab::Error::NotFound
      nil
    end

    # A row registered before hook ids were kept cannot tell its hook from
    # another row's: GitLab never returns a hook's token. A hook at our URL is
    # this row's only when no other such row names the same GitLab project and
    # no row with a kept id owns it; otherwise it stays.
    def unclaimed_hook_ids(client, repository)
      others = Repository.joins(:integration)
                         .where(integrations: { provider: "gitlab" }, full_name: repository.full_name)
                         .where.not(id: repository.id)
                         .where.not(webhook_secret: [ nil, "" ])
      return [] if others.where(gitlab_hook_id: nil).exists?

      claimed = others.pluck(:gitlab_hook_id)
      client.project_hooks(repository.full_name)
            .select { |hook| hook.url == Gitlab::AppConfig.webhook_url }
            .map(&:id) - claimed
    end

    def token_service
      @token_service ||= Gitlab::TokenService.new(@integration)
    end

    def map_project(proj)
      {
        full_name: proj.path_with_namespace,
        default_branch: proj.default_branch || "main",
        clone_url: proj.http_url_to_repo,
        is_private: proj.respond_to?(:visibility) ? proj.visibility != "public" : true,
        description: proj.description
      }
    end
  end
end
