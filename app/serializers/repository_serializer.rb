# frozen_string_literal: true

class RepositorySerializer < ApplicationSerializer
  attributes :id, :full_name, :repo_name, :source_branch, :clone_url,
             :is_private, :description, :purpose, :last_fetched_at,
             :scope_type, :scope_id, :scope_indicator, :created_at

  belongs_to :integration, serializer: IntegrationSerializer

  def repo_name
    object.repo_name
  end

  def scope_indicator
    if object.respond_to?(:scope_indicator)
      object.scope_indicator
    elsif object.scope_type == "Company"
      "company"
    else
      "project"
    end
  end
end
