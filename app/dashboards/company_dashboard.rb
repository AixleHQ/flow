# frozen_string_literal: true

require "administrate/base_dashboard"

class CompanyDashboard < Administrate::BaseDashboard
  include DashboardConcern

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    slug: Field::String,
    email_domain: Field::String,
    display_name: Field::String,
    logo_url: Field::String,
    logo: Field::Shrine,
    auto_accept_users: Field::Boolean,
    primary_color: Field::String.with_options(searchable: false),
    secondary_color: Field::String.with_options(searchable: false),
    state: Field::Select.with_options(
      include_blank: false,
      collection: ->(field) { available_states_collection(field, :state) }
    ),
    state_event: Field::Select.with_options(
      include_blank: true,
      collection: ->(field) { available_events_collection(field, :state) }
    ),
    settings: Field::JSONB,
    initial_admin_email: Field::String,
    initial_admin_password: Field::Password,
    users: Field::HasMany,
    projects: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    email_domain
    auto_accept_users
    state
    users
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    slug
    email_domain
    display_name
    logo
    logo_url
    auto_accept_users
    primary_color
    secondary_color
    state
    settings
    users
    projects
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    email_domain
    display_name
    logo
    auto_accept_users
    primary_color
    secondary_color
    state_event
    settings
  ].freeze

  FORM_ATTRIBUTES_NEW = %i[
    name
    email_domain
    display_name
    logo
    auto_accept_users
    primary_color
    secondary_color
    initial_admin_email
    initial_admin_password
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    suspended: ->(resources) { resources.suspended },
    archived: ->(resources) { resources.archived }
  }.freeze

  def display_resource(company)
    company.name
  end
end
