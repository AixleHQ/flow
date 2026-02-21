# frozen_string_literal: true

require "administrate/base_dashboard"

class AssetDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    folder: Field::String,
    status: Field::String,
    scope_type: Field::String,
    scope_id: Field::Number,
    created_by: Field::BelongsTo,
    terminal_session: Field::BelongsTo.with_options(optional: true),
    versions: Field::HasMany.with_options(class_name: "AssetVersion"),
    tags: Field::String,
    public: Field::Boolean,
    deleted_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    folder
    status
    scope_type
    created_by
    terminal_session
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    folder
    status
    scope_type
    scope_id
    created_by
    terminal_session
    versions
    tags
    public
    deleted_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    pending_review: ->(resources) { resources.pending_review },
    dismissed: ->(resources) { resources.dismissed },
    deleted: ->(resources) { resources.deleted }
  }.freeze

  def display_resource(asset)
    "#{asset.name} (#{asset.status})"
  end
end
