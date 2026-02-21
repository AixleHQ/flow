# frozen_string_literal: true

require "administrate/base_dashboard"

class TerminalSessionDashboard < Administrate::BaseDashboard
  include DashboardConcern

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    session_type: Field::String,
    agent_type: Field::String,
    state: Field::String,
    mode: Field::String,
    user: Field::BelongsTo,
    project: Field::BelongsTo.with_options(optional: true),
    session_logs: Field::HasMany,
    initial_prompt: Field::Text.with_options(truncate: 80),
    error_message: Field::Text.with_options(truncate: 80),
    container_id: Field::String,
    route_token: Field::String,
    models: Field::String,
    total_tokens: Field::Number,
    cost_cents: Field::Number,
    metadata: Field::JSONB,
    started_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    ready_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    finished_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    user
    agent_type
    session_type
    state
    mode
    cost_cents
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    session_type
    agent_type
    state
    mode
    user
    project
    initial_prompt
    error_message
    container_id
    route_token
    models
    total_tokens
    cost_cents
    metadata
    session_logs
    started_at
    ready_at
    finished_at
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(session)
    "##{session.id} #{session.agent_type} (#{session.state})"
  end
end
