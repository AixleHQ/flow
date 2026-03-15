# frozen_string_literal: true

require "administrate/base_dashboard"

class SubStepRunDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    step_run: Field::BelongsTo,
    sub_step: Field::BelongsTo,
    state: Field::String,
    data: Field::JSONB,
    note: Field::Text.with_options(truncate: 80),
    started_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    completed_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    step_run
    sub_step
    state
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    step_run
    sub_step
    state
    data
    note
    started_at
    completed_at
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(sub_step_run)
    "##{sub_step_run.id} (#{sub_step_run.state})"
  end
end
