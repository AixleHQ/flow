# frozen_string_literal: true

require "administrate/base_dashboard"

class NamespaceResourceQuotaDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    scope_type: Field::Select.with_options(
      include_blank: false,
      collection: %w[Project User]
    ),
    scope_id: Field::Number,
    cpu_requests: Field::String,
    memory_requests: Field::String,
    cpu_limits: Field::String,
    memory_limits: Field::String,
    max_pods: Field::Number,
    description: Field::Text,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    scope_type
    scope_id
    cpu_limits
    memory_limits
    max_pods
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    scope_type
    scope_id
    cpu_requests
    memory_requests
    cpu_limits
    memory_limits
    max_pods
    description
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    scope_type
    scope_id
    cpu_requests
    memory_requests
    cpu_limits
    memory_limits
    max_pods
    description
  ].freeze

  COLLECTION_FILTERS = {
    project: ->(resources) { resources.where(scope_type: "Project") },
    user: ->(resources) { resources.where(scope_type: "User") }
  }.freeze

  def display_resource(quota)
    "#{quota.scope_type} ##{quota.scope_id}"
  end
end
