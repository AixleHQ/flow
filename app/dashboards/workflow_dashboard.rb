# frozen_string_literal: true

require "administrate/base_dashboard"

class WorkflowDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String.with_options(searchable: true),
    description: Field::Text.with_options(truncate: 80),
    scope_type: Field::String,
    scope_id: Field::Number,
    config: Field::JSONB,
    deleted_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    steps: Field::HasMany,
    runs: Field::HasMany.with_options(class_name: "WorkflowRun"),
    column_workflow_bindings: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    scope_type
    deleted_at
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    description
    scope_type
    scope_id
    config
    deleted_at
    steps
    runs
    column_workflow_bindings
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.where(deleted_at: nil) },
    deleted: ->(resources) { resources.where.not(deleted_at: nil) }
  }.freeze

  def display_resource(workflow)
    workflow.name
  end
end
