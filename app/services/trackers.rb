# frozen_string_literal: true

# Provider-neutral task trackers: docs/design/task-tracker-integrations.md.
module Trackers
  # Integration provider => tracker provider class. Kept as names so this file
  # never forces a provider class to load.
  PROVIDERS = {
    "azure_devops" => "Trackers::AzureDevops::Provider",
    "github" => "Trackers::Github::Provider",
    "jira" => "Trackers::Jira::Provider",
    "linear" => "Trackers::Linear::Provider"
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

  # Trackers accept a webhook to a host they cannot reach and then fail every
  # delivery in silence, so a loopback or private host registers none.
  def self.public_webhook_url?(url)
    host = URI.parse(url.to_s).host.to_s
    return false unless host.include?(".")
    return false if host.end_with?(".local", ".internal", ".localdomain")

    !host.match?(/\A(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/)
  rescue URI::InvalidURIError
    false
  end
end
