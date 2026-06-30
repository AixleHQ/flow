# frozen_string_literal: true

class RepositoryResource < ApplicationResource
  attributes :id, :full_name, :clone_url, :source_branch, :is_private,
             :description, :purpose, :last_fetched_at, :created_at, :updated_at

  one :integration, resource: IntegrationResource

  typelize %w[company project]
  attribute :scope_indicator do |repo|
    repo.scope_indicator
  end
end
