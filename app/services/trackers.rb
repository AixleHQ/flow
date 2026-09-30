# frozen_string_literal: true

# Provider-neutral task trackers: docs/design/task-tracker-integrations.md.
module Trackers
  # Integration provider => tracker provider class. Kept as names so this file
  # never forces a provider class to load.
  PROVIDERS = {
    "azure_devops" => "Trackers::AzureDevops::Provider",
    "jira" => "Trackers::Jira::Provider"
  }.freeze

  # What tracker tools declare as `requires_integration`: not an Integration
  # provider but "this project has a usable tracker", whichever provider backs it.
  CAPABILITY = "tracker"

  def self.provider_class(provider)
    PROVIDERS[provider.to_s]&.constantize
  end

  def self.provider?(provider)
    PROVIDERS.key?(provider.to_s)
  end
end
