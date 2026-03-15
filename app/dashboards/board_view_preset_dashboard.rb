# frozen_string_literal: true

require "administrate/base_dashboard"

class BoardViewPresetDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board: Field::BelongsTo,
    user: Field::BelongsTo,
    name: Field::String,
    filters: Field::JSONB,
    shared: Field::Boolean,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    board
    user
    name
    shared
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    board
    user
    name
    filters
    shared
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(preset)
    preset.name
  end
end
