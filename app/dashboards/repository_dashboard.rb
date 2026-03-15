# frozen_string_literal: true

require "administrate/base_dashboard"

class RepositoryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    full_name: Field::String,
    source_branch: Field::String,
    clone_url: Field::String,
    description: Field::Text.with_options(truncate: 80),
    purpose: Field::Text.with_options(truncate: 80),
    is_private: Field::Boolean,
    integration: Field::BelongsTo,
    scope_type: Field::String,
    scope_id: Field::Number,
    last_fetched_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    full_name
    source_branch
    integration
    scope_type
    is_private
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    full_name
    source_branch
    clone_url
    description
    purpose
    is_private
    integration
    scope_type
    scope_id
    last_fetched_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(repository)
    repository.full_name
  end
end
