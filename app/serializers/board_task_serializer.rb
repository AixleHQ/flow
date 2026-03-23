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
    object.child_tasks.size
  end

  def comments_count
    object.task_comments.size
  end

  def assets_count
    object.task_assets.size
  end

  def recent_workflow_runs
    object.workflow_runs.sort_by { |r| r.created_at }.reverse.first(5).map do |run|
      { id: run.id, state: run.state }
    end
  end
end
