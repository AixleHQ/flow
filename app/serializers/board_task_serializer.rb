# frozen_string_literal: true

class BoardTaskSerializer < ApplicationSerializer
  attributes :id, :title, :description, :task_type, :priority,
             :assignee_id, :assignee_name, :board_column_id, :position,
             :parent_task_id, :tags,
             :children_count, :comments_count, :assets_count,
             :recent_workflow_runs,
             :created_at, :updated_at

  def assignee_name
    object.assignee&.name
  end

  def children_count
    object.child_tasks.count
  end

  def comments_count
    object.task_comments.count
  end

  def assets_count
    object.task_assets.count
  end

  def recent_workflow_runs
    object.workflow_runs.order(created_at: :desc).limit(5).map do |run|
      { id: run.id, state: run.state }
    end
  end
end
