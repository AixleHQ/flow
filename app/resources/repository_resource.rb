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
end
