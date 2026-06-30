# frozen_string_literal: true

class TaskDetailResource < BoardTaskResource
  typelize_from BoardTask

  # assignee_name / comments_count / children_count / recent_workflow_runs / pending_gates are
  # defined and annotated on BoardTaskResource and inherited here.

  typelize :string?
  attribute :description do |task|
    task.description
  end

  typelize :number
  attribute :assets_count do |task|
    task.task_assets.size
  end
end
