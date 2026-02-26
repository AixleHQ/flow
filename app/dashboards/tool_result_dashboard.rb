# frozen_string_literal: true

require "administrate/base_dashboard"

class ToolResultDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    execution_id: Field::String.with_options(searchable: true),
    state: Field::String,
    tool: Field::BelongsTo.with_options(searchable: true, searchable_fields: %w[name]),
    terminal_session: Field::BelongsTo.with_options(optional: true),
    step_run_id: Field::Number,
    exit_code: Field::Number,
    error: Field::Text.with_options(truncate: 120),
    duration_ms: Field::Number,
    stdout: Field::Shrine.with_options(url_only: true),
    stderr: Field::Shrine.with_options(url_only: true),
    result_data: Field::Shrine.with_options(url_only: true),
    output: Field::Shrine.with_options(url_only: true),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    execution_id
    tool
    state
    exit_code
    duration_ms
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    execution_id
    state
    tool
    terminal_session
    step_run_id
    exit_code
    error
    duration_ms
    stdout
    stderr
    result_data
    output
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    processing: ->(resources) { resources.where(state: "processing") },
    completed: ->(resources) { resources.where(state: "completed") },
    failed: ->(resources) { resources.where(state: "failed") },
    expired: ->(resources) { resources.where(state: "expired") }
  }.freeze

  def display_resource(tool_result)
    "#{tool_result.execution_id} (#{tool_result.state})"
  end
end
