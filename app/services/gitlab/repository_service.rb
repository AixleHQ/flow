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

    def configure(repository)
      webhook_secret = SecureRandom.hex(32)
      repository.update!(webhook_secret: webhook_secret)

      client = token_service.client
      webhook_url = "#{Settings.protocol}://#{Settings.domain}/webhooks/gitlab"
      client.add_project_hook(
        repository.full_name,
        webhook_url,
        token: webhook_secret,
        pipeline_events: true
      )
      webhook_secret
    end

    def remove(repository)
      return if repository.webhook_secret.blank?

      client = token_service.client
      webhook_url = "#{Settings.protocol}://#{Settings.domain}/webhooks/gitlab"
      hooks = client.project_hooks(repository.full_name)
      hook = hooks.find { |h| h.url == webhook_url }
      client.delete_project_hook(repository.full_name, hook.id) if hook
    rescue ::Gitlab::Error::Error => e
      Rails.logger.warn("[Gitlab::RepositoryService] Failed to remove webhook for #{repository.full_name}: #{e.message}")
    end

    private

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
