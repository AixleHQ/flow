# frozen_string_literal: true

# Provider-neutral pull requests: docs/design/bitbucket-integration.md §4.
module PullRequests
  # Integration provider => adapter class. Names, so this file never forces a
  # provider class to load.
  PROVIDERS = {
    "github" => "PullRequests::Github::Provider",
    "gitlab" => "PullRequests::Gitlab::Provider",
    "bitbucket" => "PullRequests::Bitbucket::Provider"
  }.freeze

  # What the pull_request_* tools declare as `requires_integration`: not an
  # Integration provider but "this project has a connection whose host has
  # pull-request tools", whichever provider it is.
  CAPABILITY = "pull_requests"

  # The repositories a pull-request trigger of `project` can listen to, for the
  # trigger form's picker: those on a code host, which delivers their events.
  def self.trigger_repositories(project)
    Repository.where(scope: project).joins(:integration)
              .where(integrations: { provider: Repository::CODE_HOST_PROVIDERS })
              .includes(:integration).order(:full_name).map do |repository|
      { id: repository.id, full_name: repository.full_name, provider: repository.integration.provider.to_s,
        mentions_recognized: Identity.tracker_provider(repository.integration)&.identity.present? || false }
    end
  end

  def self.provider_class(provider)
    PROVIDERS[provider.to_s]&.constantize
  end

  def self.provider?(provider)
    PROVIDERS.key?(provider.to_s)
  end
end
