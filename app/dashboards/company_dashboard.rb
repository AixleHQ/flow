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
      # Virtual AASM transition attribute (no DB column) — must not be searchable,
      # or Administrate builds a LIKE against companies.state_event and crashes.
      searchable: false,
      include_blank: true,
      collection: ->(field) { available_events_collection(field, :state) }
    ),
    settings: Field::JSONB,
    # An operator's override. A company that pays moves between these on its
    # own, through the allowance and Stripe's webhooks; setting it running here
    # without a Stripe customer starts a new trial (Admin::CompaniesController).
    billing_state: Field::Select.with_options(
      include_blank: false,
      collection: Company::BILLING_STATES
    ),
    # Virtual, so never searchable: Administrate would build a LIKE against a
    # column that is not there.
    session_concurrency_limit: CompanyCapacityField.with_options(searchable: false),
    managed_by_aixle: Field::Boolean,
    trial_started_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    trial_last_day: CompanyTrialField.with_options(searchable: false),
    initial_admin_email: Field::Email.with_options(searchable: false),
    invite_emails: Field::Text.with_options(
      searchable: false,
      input_options: { rows: 4, placeholder: "jane@example.com\njohn@example.com" }
    ),
    invite_role: Field::Select.with_options(
      searchable: false,
      include_blank: false,
      collection: -> { CompanyMembership.role.options }
    ),
    users: Field::HasMany,
    projects: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    email_domain
    state
    billing_state
    managed_by_aixle
    session_concurrency_limit
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
    billing_state
    trial_started_at
    trial_last_day
    managed_by_aixle
    settings
    session_concurrency_limit
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
    managed_by_aixle
    billing_state
    trial_last_day
    settings
    session_concurrency_limit
    invite_emails
    invite_role
  ].freeze

  FORM_ATTRIBUTES_NEW = %i[
    name
    email_domain
    display_name
    logo
    auto_accept_users
    primary_color
    secondary_color
    managed_by_aixle
    trial_last_day
    session_concurrency_limit
    initial_admin_email
    invite_emails
    invite_role
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    suspended: ->(resources) { resources.suspended },
    archived: ->(resources) { resources.archived },
    trialing: ->(resources) { resources.where(billing_state: "trialing") },
    billing_blocked: ->(resources) { resources.where(billing_state: "blocked") },
    managed_by_aixle: ->(resources) { resources.where(managed_by_aixle: true) }
  }.freeze

  # Trials exist only where we host; anywhere else the field could only be refused.
  def form_attributes(action = nil)
    Deployment.saas? ? super : super - [ :trial_last_day ]
  end

  def display_resource(company)
    company.name
  end
end
