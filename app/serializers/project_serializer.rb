# frozen_string_literal: true

class ProjectSerializer < ApplicationSerializer
  attributes :id, :name, :description, :slug, :state, :company_id, :owner_id,
             :collaborators_count, :last_activity_at, :created_at, :updated_at

  def collaborators_count
    object.project_collaborators.size
  end

  def last_activity_at
    object.terminal_sessions.maximum(:started_at)
  end
end
