# frozen_string_literal: true

require "administrate/base_dashboard"

class UserDashboard < Administrate::BaseDashboard
  include DashboardConcern
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :company

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    email: Field::String,
    name: Field::String,
    password: Field::Password.with_options(export: false),
    password_confirmation: Field::Password.with_options(export: false),
    role: Field::Select.with_options(
      include_blank: false,
      collection: ->(field) { available_states_collection(field, :role) }
    ),
    state: Field::Select.with_options(
      include_blank: false,
      collection: ->(field) { available_states_collection(field, :state) }
    ),
    state_event: Field::Select.with_options(
      # Virtual AASM transition attribute (no DB column) — must not be searchable,
      # or Administrate builds a LIKE against users.state_event and crashes.
      searchable: false,
      include_blank: true,
      collection: ->(field) { available_events_collection(field, :state) }
    ),
    company: Field::BelongsTo,
    owned_projects: Field::HasMany,
    collaborated_projects: Field::HasMany,
    project_collaborators: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    email
    name
    role
    state
    company
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    email
    name
    role
    state
    company
    owned_projects
    collaborated_projects
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    email
    name
    password
    password_confirmation
    role
    state_event
    company
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    suspended: ->(resources) { resources.suspended },
    archived: ->(resources) { resources.archived },
    super_admin: ->(resources) { resources.super_admin },
    admin: ->(resources) { resources.admin },
    collaborator: ->(resources) { resources.collaborator }
  }.freeze

  def display_resource(user)
    "#{user.name} (#{user.email})"
  end
end
