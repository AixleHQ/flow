# frozen_string_literal: true

require "administrate/base_dashboard"

class BoardColumnDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :board

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board: Field::BelongsTo,
    name: Field::String,
    position: Field::Number,
    purpose: Field::Text.with_options(truncate: 80),
    board_tasks: Field::HasMany,
    column_workflow_binding: Field::HasOne,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    board
    name
    position
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    board
    name
    position
    purpose
    board_tasks
    column_workflow_binding
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(column)
    "#{column.name} (##{column.position})"
  end
end
