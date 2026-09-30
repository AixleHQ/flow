# frozen_string_literal: true

class TaskDetailResource < BoardTaskResource
  typelize_from BoardTask

  # assignee_name / comments_count / children_count / recent_workflow_runs / pending_gates are
  # defined and annotated on BoardTaskResource and inherited here.

  typelize "string | null"
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
  typelize "string | null"
  attribute :parent_task_title do |task|
    task.parent_task&.title
  end

  # An epic's children used to be found by filtering the board's task list, which only worked
  # while the board held every task. Columns now load a page at a time, so the children come with
  # the task itself. (Nested keys are camelized — see the note on ApplicationResource#to_h.)
  typelize "Array<{ id: number; title: string; taskType: string }>"
  attribute :child_tasks do |task|
    task.child_tasks.sort_by(&:position).map do |child|
      { id: child.id, title: child.title, task_type: child.task_type.to_s }
    end
  end

  # The tracker issues this task is about, read-only. Only the detail view needs
  # them, so the board's task list does not pay for the lookup.
  typelize "Array<{ provider: string; key: string | null; url: string | null }>"
  attribute :tracker_issues do |task|
    task.external_resources.tracker_issues.order(:created_at).map do |link|
      { provider: link.provider, key: link.key || link.external_id, url: link.url }
    end
  end
end
