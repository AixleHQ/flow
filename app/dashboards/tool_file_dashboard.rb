# frozen_string_literal: true

require "administrate/base_dashboard"

class ToolFileDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :tool

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    tool: Field::BelongsTo,
    path: Field::String,
    content: Field::Text.with_options(truncate: 80),
    file: Field::Shrine.with_options(url_only: true),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    tool
    path
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    tool
    path
    content
    file
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(tool_file)
    "#{tool_file.path} (##{tool_file.id})"
  end
end
