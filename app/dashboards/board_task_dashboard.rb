# frozen_string_literal: true

require "administrate/base_dashboard"

class BoardTaskDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board: Field::BelongsTo,
    board_column: Field::BelongsTo,
    assignee: Field::BelongsTo.with_options(class_name: "User", optional: true),
    parent_task: Field::BelongsTo.with_options(class_name: "BoardTask", optional: true),
    title: Field::String,
    description: Field::Text.with_options(truncate: 80),
    task_type: Field::Select.with_options(
      include_blank: false,
      collection: %w[epic story bug not_specified]
    ),
    priority: Field::Select.with_options(
      include_blank: false,
      collection: %w[low medium high critical]
    ),
    position: Field::Number,
    tags: Field::String,
    child_tasks: Field::HasMany.with_options(class_name: "BoardTask"),
    task_comments: Field::HasMany,
    task_assets: Field::HasMany,
    workflow_runs: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    title
    board
    board_column
    task_type
    priority
    assignee
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    title
    board
    board_column
    assignee
    parent_task
    description
    task_type
    priority
    position
    tags
    child_tasks
    task_comments
    task_assets
    workflow_runs
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(task)
    "##{task.id} #{task.title}"
  end
end
