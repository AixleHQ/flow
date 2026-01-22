# frozen_string_literal: true

require "administrate/base_dashboard"

class CompanyDashboard < Administrate::BaseDashboard
  include DashboardConcern

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    name: Field::String,
    slug: Field::String,
    display_name: Field::String,
    logo_url: Field::String,
    primary_color: Field::String,
    secondary_color: Field::String,
    state: Field::Select.with_options(
      include_blank: false,
      collection: ->(field) { available_states_collection(field, :state) }
    ),
    settings: Field::JSONB,
    users: Field::HasMany,
    projects: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    slug
    state
    users
    projects
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    slug
    display_name
    logo_url
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
    display_name
    logo_url
    primary_color
    secondary_color
    state
    settings
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
