# frozen_string_literal: true

require "administrate/base_dashboard"

class SkillDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    title: Field::String,
    package: Field::String,
    source: Field::String,
    source_url: Field::String,
    install_count: Field::Number,
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
    package
    source
    scope_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    title
    package
    source
    source_url
    install_count
    description
    content
    scope_type
    scope_id
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(skill)
    skill.title.presence || skill.name
  end
end
