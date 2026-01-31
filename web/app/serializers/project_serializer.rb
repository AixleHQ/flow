# frozen_string_literal: true

class ProjectSerializer < ApplicationSerializer
  attributes :id, :name, :description, :slug, :state, :company_id, :owner_id,
             :collaborators_count, :last_activity_at, :created_at, :updated_at

  def collaborators_count
    object.project_collaborators.count
  end

  def last_activity_at
    object.terminal_sessions.order(started_at: :desc).limit(1).pick(:started_at)
  end
end
