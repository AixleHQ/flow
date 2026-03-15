# frozen_string_literal: true

require "administrate/base_dashboard"

class ToolDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String.with_options(searchable: true),
    display_name: Field::String,
    kind: Field::String,
    execution_mode: Field::String,
    description: Field::Text.with_options(truncate: 80),
    docker_image: Field::String,
    command: Field::Text.with_options(truncate: 80),
    enabled: Field::Boolean,
    input_schema: Field::JSONB,
    required_config_items: Field::JSONB,
    scope_type: Field::String,
    scope_id: Field::Number,
    tool_files: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    display_name
    kind
    execution_mode
    enabled
    scope_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    display_name
    kind
    execution_mode
    description
    docker_image
    command
    enabled
    input_schema
    required_config_items
    scope_type
    scope_id
    tool_files
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    custom: ->(resources) { resources.where(kind: :custom) },
    system: ->(resources) { resources.where(kind: :system) },
    internal: ->(resources) { resources.where(kind: :internal) },
    enabled: ->(resources) { resources.where(enabled: true) }
  }.freeze

  def display_resource(tool)
    tool.display_name.presence || tool.name
  end
end
