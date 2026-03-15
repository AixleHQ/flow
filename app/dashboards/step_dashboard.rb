# frozen_string_literal: true

require "administrate/base_dashboard"

class StepDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    workflow: Field::BelongsTo,
    agent: Field::BelongsTo.with_options(optional: true),
    name: Field::String.with_options(searchable: true),
    description: Field::Text.with_options(truncate: 80),
    instructions: Field::Text.with_options(truncate: 80),
    position: Field::Number,
    skip_policy: Field::String,
    on_failure: Field::String,
    max_retries: Field::Number,
    allow_non_interactive: Field::Boolean,
    mount_repositories: Field::Boolean,
    required_agent_runtime: Field::String,
    depends_on_step_ids: Field::JSONB,
    input_asset_specs: Field::JSONB,
    output_asset_specs: Field::JSONB,
    tool_ids: Field::JSONB,
    skill_ids: Field::JSONB,
    mcp_server_ids: Field::JSONB,
    sub_steps: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    workflow
    name
    position
    skip_policy
    on_failure
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    workflow
    agent
    name
    description
    instructions
    position
    skip_policy
    on_failure
    max_retries
    allow_non_interactive
    mount_repositories
    required_agent_runtime
    depends_on_step_ids
    input_asset_specs
    output_asset_specs
    tool_ids
    skill_ids
    mcp_server_ids
    sub_steps
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(step)
    "#{step.name} (##{step.id})"
  end
end
