# frozen_string_literal: true

class BoardTaskSerializer < ApplicationSerializer
  attributes :id, :title, :description, :task_type, :priority,
             :assignee_id, :assignee_name, :board_column_id, :position,
             :parent_task_id, :tags,
             :children_count, :comments_count, :assets_count,
             :active_workflow_run,
             :created_at, :updated_at

  def assignee_name
    object.assignee&.name
  end

  def children_count
    object.child_tasks.size
  end

  def comments_count
    object.task_comments.size
  end

  def assets_count
    object.task_assets.size
  end

  def active_workflow_run
    run = object.workflow_runs.find_by(state: %w[pending running paused])
    return nil unless run

    { id: run.id, status: run.state }
  end
end
