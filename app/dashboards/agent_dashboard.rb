# frozen_string_literal: true

require "administrate/base_dashboard"

class AgentDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    title: Field::String,
    persona: Field::Text.with_options(truncate: 80),
    communication_style: Field::Text.with_options(truncate: 80),
    principles: Field::Text.with_options(truncate: 80),
    icon: Field::String,
    source: Field::Select.with_options(
      include_blank: false,
      collection: %w[custom bmad_import]
    ),
    scope_type: Field::String,
    scope_id: Field::Number,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    title
    source
    scope_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    title
    source
    persona
    communication_style
    principles
    icon
    scope_type
    scope_id
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    title
    source
    persona
    communication_style
    principles
    icon
    scope_type
    scope_id
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(agent)
    agent.title.presence || agent.name
  end
end
