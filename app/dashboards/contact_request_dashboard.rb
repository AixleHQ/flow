# frozen_string_literal: true

require "administrate/base_dashboard"

class ContactRequestDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::String,
    first_name: Field::String,
    last_name: Field::String,
    email: Field::String,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    first_name
    last_name
    email
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    first_name
    last_name
    email
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  def display_resource(contact)
    "#{contact.first_name} #{contact.last_name}"
  end
end
