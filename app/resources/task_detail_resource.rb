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

  # The board loads only active tasks, so the client cannot always resolve the parent epic from
  # the board's task list (an archived epic is not in it). Name it here so the task detail view
  # can always show which epic the task belongs to.
  typelize :string?
  attribute :parent_task_title do |task|
    task.parent_task&.title
  end
end
