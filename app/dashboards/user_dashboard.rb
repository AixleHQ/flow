# frozen_string_literal: true

require "administrate/base_dashboard"

class UserDashboard < Administrate::BaseDashboard
  include DashboardConcern

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    email: Field::String,
    name: Field::String,
    password: Field::Password.with_options(export: false),
    password_confirmation: Field::Password.with_options(export: false),
    super_admin: Field::Boolean,
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
    companies: Field::HasMany,
    owned_projects: Field::HasMany,
    collaborated_projects: Field::HasMany,
    project_collaborators: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    # Soft-delete timestamp. Blank for active users; set when an admin deletes a
    # user (see Admin::UsersController#destroy / User#soft_delete!). Surfaced here
    # so admins can see which accounts have been soft-deleted and when.
    deleted_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    email
    name
    super_admin
    state
    created_at
    deleted_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    email
    name
    super_admin
    state
    companies
    owned_projects
    collaborated_projects
    created_at
    updated_at
    deleted_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    email
    name
    password
    password_confirmation
    super_admin
    state_event
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    suspended: ->(resources) { resources.suspended },
    archived: ->(resources) { resources.archived },
    # `admin`/`collaborator` were Enumerize role scopes on users.role, which is
    # gone — the per-company role lives on CompanyMembership.
    super_admin: ->(resources) { resources.where(super_admin: true) },
    deleted: ->(resources) { resources.deleted },
    not_deleted: ->(resources) { resources.not_deleted }
  }.freeze

  def display_resource(user)
    "#{user.name} (#{user.email})"
  end
end
