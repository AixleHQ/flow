# frozen_string_literal: true

require "administrate/base_dashboard"

class WorkflowRunDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :workflow

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    workflow: Field::BelongsTo,
    project: Field::BelongsTo,
    user: Field::BelongsTo,
    board_task: Field::BelongsTo.with_options(optional: true),
    state: Field::String,
    mode: Field::String,
    agent_runtime: Field::String,
    shared_context: Field::JSONB,
    step_overrides: Field::JSONB,
    input_asset_ids: Field::JSONB,
    repository_ids: Field::JSONB,
    started_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    completed_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    step_runs: Field::HasMany,
    workflow_run_assets: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    workflow
    project
    user
    state
    mode
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    workflow
    project
    user
    board_task
    state
    mode
    agent_runtime
    shared_context
    step_overrides
    input_asset_ids
    repository_ids
    started_at
    completed_at
    step_runs
    workflow_run_assets
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.where(state: %i[pending running paused]) },
    completed: ->(resources) { resources.where(state: :completed) },
    failed: ->(resources) { resources.where(state: :failed) }
  }.freeze

  def display_resource(workflow_run)
    "##{workflow_run.id} (#{workflow_run.state})"
  end
end
