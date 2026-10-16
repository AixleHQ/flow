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

  def self.provider_class(provider)
    PROVIDERS[provider.to_s]&.constantize
  end

  def self.provider?(provider)
    PROVIDERS.key?(provider.to_s)
  end
end
