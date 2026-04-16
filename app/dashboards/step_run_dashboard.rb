# frozen_string_literal: true

require "administrate/base_dashboard"

class StepRunDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :workflow_run

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    workflow_run: Field::BelongsTo,
    step: Field::BelongsTo,
    terminal_session: Field::BelongsTo.with_options(optional: true),
    state: Field::String,
    error_message: Field::Text.with_options(truncate: 80),
    skip_reason: Field::String,
    step_note: Field::Text.with_options(truncate: 80),
    started_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    completed_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    sub_step_runs: Field::HasMany,
    produced_workflow_run_assets: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    workflow_run
    step
    state
    started_at
    completed_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    workflow_run
    step
    terminal_session
    state
    error_message
    skip_reason
    step_note
    started_at
    completed_at
    sub_step_runs
    produced_workflow_run_assets
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    running: ->(resources) { resources.where(state: :running) },
    completed: ->(resources) { resources.where(state: :completed) },
    failed: ->(resources) { resources.where(state: :failed) }
  }.freeze

  def display_resource(step_run)
    "##{step_run.id} (#{step_run.state})"
  end
end
