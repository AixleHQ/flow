# frozen_string_literal: true

require "administrate/base_dashboard"

class TaskCommentDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :board_task

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board_task: Field::BelongsTo,
    author: Field::BelongsTo,
    author_type: Field::String,
    body: Field::Text.with_options(truncate: 80),
    tags: Field::String,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    board_task
    author
    author_type
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    board_task
    author
    author_type
    body
    tags
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(comment)
    "##{comment.id} (#{comment.author_type})"
  end
end
