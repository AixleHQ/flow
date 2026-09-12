# frozen_string_literal: true

class RepositoryResource < ApplicationResource
  attributes :id, :full_name, :clone_url, :source_branch, :is_private,
             :description, :purpose, :last_fetched_at, :created_at, :updated_at

  # Null for public repositories: they are attached without credentials, so
  # there is no integration behind them.
  typelize "Integration | null"
  attribute :integration do |repo|
    next nil if repo.integration.blank?

    IntegrationResource.new(repo.integration).to_h
  end

  typelize :boolean
  attribute :public_source do |repo|
    repo.public_source?
  end

  typelize %w[company project]
  attribute :scope_indicator do |repo|
    repo.scope_indicator
  end

  # Azure identity. The GUIDs are what every API call routes on — `full_name`
  # is a display value for these rows and a rename changes it.
  typelize :string?
  attribute :external_id do |repo|
    repo.external_id
  end

  typelize :string?
  attribute :provider do |repo|
    repo.provider
  end

  # Display halves of the Azure `full_name`, so the UI can show organization and
  # project without parsing the discriminator itself.
  typelize "{ organization: string; project: string; repository: string } | null"
  attribute :azure_display do |repo|
    parts = repo.azure_display_parts
    parts.present? ? parts : nil
  end
end
