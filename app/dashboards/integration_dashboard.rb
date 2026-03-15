# frozen_string_literal: true

require "administrate/base_dashboard"

class IntegrationDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    provider: Field::Select.with_options(
      include_blank: false,
      collection: %w[github linear]
    ),
    status: Field::Select.with_options(
      include_blank: false,
      collection: %w[active inactive error]
    ),
    company: Field::BelongsTo,
    connected_by: Field::BelongsTo.with_options(class_name: "User"),
    settings: Field::JSONB,
    repositories: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    provider
    status
    company
    connected_by
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    provider
    status
    company
    connected_by
    settings
    repositories
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(integration)
    "#{integration.name} (#{integration.provider})"
  end
end
