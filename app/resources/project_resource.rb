# frozen_string_literal: true

class ProjectResource < ApplicationResource
  attributes :id, :name, :description, :slug, :state, :created_at, :updated_at

  attribute :collaborators_count do |project|
    if project.respond_to?(:cached_collaborators_count)
      project.cached_collaborators_count.to_i
    else
      project.project_collaborators.size
    end
  end

  attribute :members_count do |project|
    if project.respond_to?(:cached_collaborators_count)
      project.cached_collaborators_count.to_i + 1
    else
      project.project_collaborators.size + 1
    end
  end

  attribute :last_activity_at do |project|
    if project.respond_to?(:cached_last_activity_at)
      project.cached_last_activity_at
    else
      project.terminal_sessions.maximum(:started_at)
    end
  end

  attribute :sessions_count do |project|
    if project.respond_to?(:cached_sessions_count)
      project.cached_sessions_count.to_i
    else
      project.terminal_sessions.count
    end
  end

  attribute :workflows_count do |project|
    if project.respond_to?(:cached_workflows_count)
      project.cached_workflows_count.to_i
    else
      project.workflows.where(deleted_at: nil).count
    end
  end

  attribute :board_tasks_count do |project|
    if project.respond_to?(:cached_board_tasks_count)
      project.cached_board_tasks_count.to_i
    else
      project.board&.board_tasks&.count || 0
    end
  end
end
