# frozen_string_literal: true

class ProjectSerializer < ApplicationSerializer
  attributes :id, :name, :description, :slug, :state, :company_id, :owner_id,
             :collaborators_count, :last_activity_at, :created_at, :updated_at

  def collaborators_count
    object.project_collaborators.count
  end

  def last_activity_at
    # TODO: Implement when terminal_sessions or other activity tracking is added
    nil
  end
end
