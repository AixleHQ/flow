# frozen_string_literal: true

require "administrate/base_dashboard"

class SessionConcurrencyLimitDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    scope_type: Field::Select.with_options(
      include_blank: false,
      collection: %w[Project User]
    ),
    scope_id: Field::Number,
    max_sessions: Field::Number,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    scope_type
    scope_id
    max_sessions
    updated_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    scope_type
    scope_id
    max_sessions
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    scope_type
    scope_id
    max_sessions
  ].freeze

  COLLECTION_FILTERS = {
    project: ->(resources) { resources.where(scope_type: "Project") },
    user: ->(resources) { resources.where(scope_type: "User") }
  }.freeze

  def display_resource(limit)
    "#{limit.scope_type} ##{limit.scope_id}: #{limit.max_sessions} concurrent sessions"
  end
end
