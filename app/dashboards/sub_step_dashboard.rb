# frozen_string_literal: true

require "administrate/base_dashboard"

class SubStepDashboard < Administrate::BaseDashboard
  include SkipAdministrateCollectionIncludes
  skip_administrate_collection_includes :step

  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    step: Field::BelongsTo,
    name: Field::String.with_options(searchable: true),
    instructions: Field::Text.with_options(truncate: 80),
    position: Field::Number,
    required: Field::Boolean,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    step
    name
    position
    required
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    step
    name
    instructions
    position
    required
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(sub_step)
    "#{sub_step.name} (##{sub_step.id})"
  end
end
