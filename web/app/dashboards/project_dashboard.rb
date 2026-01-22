# frozen_string_literal: true

require "administrate/base_dashboard"

class ProjectDashboard < Administrate::BaseDashboard
  include DashboardConcern

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    slug: Field::String,
    description: Field::Text,
    state: Field::Select.with_options(
      include_blank: false,
      collection: ->(field) { available_states_collection(field, :state) }
    ),
    company: Field::BelongsTo,
    owner: Field::BelongsTo,
    project_collaborators: Field::HasMany,
    collaborators: Field::HasMany,
    settings: Field::JSONB,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    slug
    state
    company
    owner
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    slug
    description
    state
    company
    owner
    collaborators
    settings
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    description
    state
    company
    owner
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    paused: ->(resources) { resources.paused },
    archived: ->(resources) { resources.archived }
  }.freeze

  def display_resource(project)
    project.name
  end
end
