# frozen_string_literal: true

require "administrate/base_dashboard"

class SessionConcurrencyLimitDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    scope_type: Field::Select.with_options(
      include_blank: false,
      collection: SessionConcurrencyLimit::SCOPE_TYPES
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

  # A company row is what the installation sells; a project row is a reservation
  # drawn from it. A stray legacy row is visible by its absence from both filters.
  COLLECTION_FILTERS = {
    company: ->(resources) { resources.for_companies },
    project: ->(resources) { resources.for_projects }
  }.freeze

  def display_resource(limit)
    "#{limit.scope_type} ##{limit.scope_id}: #{limit.max_sessions} concurrent sessions"
  end
end
