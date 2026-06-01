# frozen_string_literal: true

class WorkflowTemplateResource < ApplicationResource
  attributes :id, :name, :description, :use_case, :visibility, :created_at, :updated_at

  attribute :owner_name do |template|
    template.owner.name
  end

  attribute :owner_id do |template|
    template.owner_id
  end

  attribute :latest_version_number do |template|
    template.current_version&.version_number
  end

  attribute :current_version_id do |template|
    template.current_version_id
  end

  attribute :last_updated_at do |template|
    template.current_version&.published_at || template.updated_at
  end

  attribute :projects_count do |template|
    template.projects_count
  end

  attribute :steps_count do |template|
    template.current_version&.workflow&.steps&.count { |s| s.deleted_at.nil? } || 0
  end
end
