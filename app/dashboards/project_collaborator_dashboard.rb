# frozen_string_literal: true

require "administrate/base_dashboard"

class ProjectCollaboratorDashboard < Administrate::BaseDashboard
  include DashboardConcern

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    project: Field::BelongsTo,
    user: Field::BelongsTo,
    created_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p"),
    updated_at: Field::DateTime.with_options(format: "%B %-d, %Y at %l:%M %p")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    project
    user
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    project
    user
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    project
    user
  ].freeze

  def display_resource(project_collaborator)
    "#{project_collaborator.user.name} → #{project_collaborator.project.name}"
  end
end
