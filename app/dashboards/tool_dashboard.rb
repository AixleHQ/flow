# frozen_string_literal: true

require "administrate/base_dashboard"

class ToolDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String.with_options(searchable: true),
    display_name: Field::String,
    source: Field::String,
    tags: Field::JSONB,
    kind: Field::String,
    execution_mode: Field::String,
    user_attachable: Field::Boolean,
    requires_integration: Field::String,
    description: Field::Text.with_options(truncate: 80),
    docker_image: Field::String,
    command: Field::Text.with_options(truncate: 80),
    enabled: Field::Boolean,
    input_schema: Field::JSONB,
    required_config_items: Field::JSONB,
    scope_type: Field::String,
    scope_id: Field::Number,
    tool_files: Field::HasMany,
    deleted_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    display_name
    source
    tags
    execution_mode
    enabled
    scope_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    display_name
    source
    tags
    user_attachable
    requires_integration
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
    deleted_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  # platform = reconciler-owned shadow rows of code-defined tools (source: code);
  # custom = user-authored docker tools (source: db). Tag filters follow the
  # closed vocabulary in the tool DSL. kind is legacy — dropped in Stage 4.
  COLLECTION_FILTERS = {
    platform: ->(resources) { resources.where(source: "code") },
    custom: ->(resources) { resources.where(source: "db") },
    enabled: ->(resources) { resources.where(enabled: true) },
    deleted: ->(resources) { resources.where.not(deleted_at: nil) },
    board: ->(resources) { resources.where("tools.tags @> ?", %w[board].to_json) },
    builder: ->(resources) { resources.where("tools.tags @> ?", %w[builder].to_json) },
    coder: ->(resources) { resources.where("tools.tags @> ?", %w[coder].to_json) },
    slack: ->(resources) { resources.where("tools.tags @> ?", %w[slack].to_json) }
  }.freeze

  def display_resource(tool)
    tool.display_name.presence || tool.name
  end
end
