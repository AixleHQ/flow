# frozen_string_literal: true

require "administrate/base_dashboard"

class SessionLogDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :terminal_session

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    terminal_session: Field::BelongsTo,
    name: Field::String,
    content_type: Field::String,
    file_size: Field::Number,
    file: Field::Shrine.with_options(url_only: true),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    terminal_session
    name
    content_type
    file_size
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    terminal_session
    name
    content_type
    file_size
    file
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  def display_resource(log)
    log.name
  end
end
