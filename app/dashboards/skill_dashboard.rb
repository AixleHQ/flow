# frozen_string_literal: true

require "administrate/base_dashboard"

class SkillDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    title: Field::String,
    kind: Field::Select.with_options(
      include_blank: false,
      collection: %w[internal custom]
    ),
    description: Field::Text.with_options(truncate: 80),
    content: Field::Text.with_options(truncate: 80),
    scope_type: Field::String,
    scope_id: Field::Number,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    title
    kind
    scope_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    title
    kind
    description
    content
    scope_type
    scope_id
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    internal: ->(resources) { resources.internal_skills },
    custom: ->(resources) { resources.custom_skills }
  }.freeze

  def display_resource(skill)
    skill.title.presence || skill.name
  end
end
