# frozen_string_literal: true

class ProjectSerializer < ApplicationSerializer
  attributes :id, :name, :description, :slug, :state, :company_id, :owner_id,
             :collaborators_count, :last_activity_at, :created_at, :updated_at

  def collaborators_count
    object.project_collaborators.size
  end

  def last_activity_at
    if object.respond_to?(:cached_last_activity_at) && object.has_attribute?(:cached_last_activity_at)
      object.cached_last_activity_at
    else
      object.terminal_sessions.maximum(:started_at)
    end
  end
end
