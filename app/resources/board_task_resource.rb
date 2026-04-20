# frozen_string_literal: true

class BoardTaskResource < ApplicationResource
  attributes :id, :title, :description, :task_type, :priority,
             :assignee_id, :board_column_id, :position,
             :parent_task_id, :tags, :created_at, :updated_at

  attribute :assignee_name do |task|
    task.assignee&.name
  end

  attribute :comments_count do |task|
    task.task_comments.size
  end

  attribute :children_count do |task|
    task.child_tasks.size
  end

  attribute :assets_count do |task|
    task.task_assets.size
  end

  attribute :recent_workflow_runs do |task|
    task.workflow_runs.sort_by { |r| r.created_at }.last(5).reverse.map do |run|
      { id: run.id, state: run.state, created_at: run.created_at.iso8601 }
    end
  end

  attribute :pending_waits do |task|
    task.pending_task_waits.map do |wait|
      { id: wait.id, wait_type: wait.wait_type, metadata: wait.metadata, created_at: wait.created_at.iso8601 }
    end
  end
end
