# frozen_string_literal: true

module Repositories
  # Refuses a GitHub repository its connection could see but not clone, when it is
  # added rather than when the first session fails on it: a fine-grained token with
  # only Metadata lists the repository and git still answers 403.
  module CloneAccess
    module_function

    # nil when the repository can be cloned, or when GitHub could not be asked: an
    # outage must not stop a repository from being added.
    def refusal(integration, full_name)
      return nil unless integration&.github? && full_name.present?
      return nil unless RepositoryService.for(integration).contents_readable?(full_name) == false

      "The GitHub connection #{integration.name} can see #{full_name} but not its contents, so sessions cannot clone it. " \
        "Give the token access to this repository with Contents: Read (Read and write for agents that push)."
    rescue StandardError => e
      Rails.logger.warn("[Repositories::CloneAccess] could not check #{full_name}: #{e.class}")
      nil
    end
  end
end
