# frozen_string_literal: true

module Repositories
  # The CI webhook a repository's gates resolve on. A GitLab project needs its own
  # hook, carrying this repository's secret — the endpoint authenticates each
  # delivery by it. GitHub delivers through the app installation and Azure DevOps
  # through its service hooks, so there is nothing to register for them.
  #
  # Best effort: a token without Maintainer rights cannot add a hook, and the gate
  # reconciler still resolves the gates, only later. The failure is logged, never
  # raised into adding or removing the repository.
  module CiWebhook
    module_function

    def register(repository)
      return unless gitlab?(repository)

      Gitlab::RepositoryService.new(repository.integration).configure(repository)
    rescue StandardError => e
      Rails.logger.warn("[CiWebhook] Could not register the GitLab hook for #{repository.full_name}: #{e.class}: #{e.message}")
      nil
    end

    def unregister(repository)
      return unless gitlab?(repository)

      Gitlab::RepositoryService.new(repository.integration).remove(repository)
    rescue StandardError => e
      Rails.logger.warn("[CiWebhook] Could not remove the GitLab hook for #{repository.full_name}: #{e.class}: #{e.message}")
      nil
    end

    def gitlab?(repository)
      repository.integration&.provider.to_s == "gitlab"
    end
  end
end
