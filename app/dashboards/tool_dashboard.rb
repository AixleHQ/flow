# frozen_string_literal: true

require "administrate/base_dashboard"

class ToolDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String.with_options(searchable: true),
    display_name: Field::String,
    kind: Field::String,
    execution_mode: Field::String,
    scope_type: Field::String,
    scope_id: Field::Number,
    docker_image: Field::String,
    enabled: Field::Boolean,
    description: Field::Text.with_options(truncate: 100),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    kind
    execution_mode
    enabled
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    display_name
    kind
    execution_mode
    scope_type
    scope_id
    docker_image
    enabled
    description
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(tool)
    tool.display_name.presence || tool.name
  end
end
