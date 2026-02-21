# frozen_string_literal: true

require "administrate/base_dashboard"

class AssetVersionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    asset: Field::BelongsTo,
    uploaded_by: Field::BelongsTo,
    version: Field::Number,
    source: Field::String,
    content_type: Field::String,
    file_size: Field::Number,
    file: Field::Shrine.with_options(url_only: true),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    asset
    version
    source
    file_size
    uploaded_by
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    asset
    version
    source
    content_type
    file_size
    file
    uploaded_by
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  def display_resource(version)
    "v#{version.version} (#{version.source})"
  end
end
