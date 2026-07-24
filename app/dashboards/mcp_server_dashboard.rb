# frozen_string_literal: true

require "administrate/base_dashboard"

class MCPServerDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    kind: Field::Select.with_options(
      include_blank: false,
      collection: %w[internal custom]
    ),
    transport: Field::Select.with_options(
      include_blank: false,
      collection: %w[http sse stdio]
    ),
    url: Field::String,
    command: Field::String,
    enabled: Field::Boolean,
    description: Field::Text.with_options(truncate: 80),
    scope_type: Field::String,
    scope_id: Field::Number,
    headers: Field::JSONB,
    env: Field::JSONB,
    args: Field::JSONB,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    kind
    transport
    enabled
    scope_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    kind
    transport
    url
    command
    enabled
    description
    scope_type
    scope_id
    headers
    env
    args
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    internal: ->(resources) { resources.internal_servers },
    custom: ->(resources) { resources.custom_servers },
    enabled: ->(resources) { resources.enabled }
  }.freeze

  def display_resource(mcp_server)
    mcp_server.name
  end
end
