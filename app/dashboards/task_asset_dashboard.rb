# frozen_string_literal: true

require "administrate/base_dashboard"

class TaskAssetDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :board_task

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board_task: Field::BelongsTo,
    author: Field::BelongsTo,
    author_type: Field::String,
    name: Field::String,
    file: Field::Shrine.with_options(url_only: true),
    tags: Field::String,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    board_task
    author
    name
    author_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    board_task
    author
    author_type
    name
    file
    tags
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(asset)
    "#{asset.name} (##{asset.id})"
  end
end
