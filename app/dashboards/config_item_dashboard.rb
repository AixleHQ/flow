# frozen_string_literal: true

require "administrate/base_dashboard"

class ConfigItemDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    description: Field::Text.with_options(truncate: 80),
    item_type: Field::Select.with_options(
      include_blank: false,
      collection: %w[secret variable]
    ),
    scope_type: Field::String,
    scope_id: Field::Number,
    display_value: Field::String,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    item_type
    scope_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    description
    item_type
    scope_type
    scope_id
    display_value
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(config_item)
    "#{config_item.name} (#{config_item.item_type})"
  end
end
