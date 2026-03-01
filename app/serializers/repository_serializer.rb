# frozen_string_literal: true

class RepositorySerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :full_name, :repo_name, :source_branch, :clone_url,
             :is_private, :description, :purpose, :last_fetched_at,
             :scope_type, :scope_id, :created_at

  belongs_to :integration, serializer: IntegrationSerializer

  def repo_name
    object.repo_name
  end
end
