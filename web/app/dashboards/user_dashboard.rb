require "administrate/base_dashboard"

class UserDashboard < Administrate::BaseDashboard
  include DashboardConcern

  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    email: Field::String,
    name: Field::String,
    password: Field::Password.with_options(export: false),
    password_confirmation: Field::Password.with_options(export: false),
    roles: Field::HasMany,
    status: Field::Select.with_options(
      include_blank: false,
      collection: ->(field) { available_states_collection(field) }
    ),
    status_event: Field::Select.with_options(
      include_blank: true,
      export: false,
      searchable: false,
      collection: ->(field) { available_events_collection(field) }
    ),
    audits: Field::HasMany,
    accounts: Field::HasMany,
    changed_items: Field::HasMany,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    email
    name
    status
    accounts
    created_at
    updated_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    email
    name
    status
    created_at
    updated_at
    accounts
    roles
    audits
    changed_items
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    email
    name
    password
    password_confirmation
    accounts
    roles
    status
    status_event
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    draft: ->(resources) { resources.draft },
    archived: ->(resources) { resources.archived }
  }.freeze

  # Overwrite this method to customize how users are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(user)
  #   "User ##{user.id}"
  # end
  def display_resource(user)
    "#{user.name} (#{user.email})"
  end
end
