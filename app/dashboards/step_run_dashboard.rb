# frozen_string_literal: true

require "administrate/base_dashboard"

class StepRunDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    state: Field::String,
    workflow_run_id: Field::Number,
    step_id: Field::Number,
    terminal_session: Field::BelongsTo.with_options(optional: true),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id state step_id created_at].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id state workflow_run_id step_id terminal_session created_at].freeze
  FORM_ATTRIBUTES = %i[].freeze
  COLLECTION_FILTERS = {}.freeze

  def display_resource(step_run)
    "##{step_run.id} (#{step_run.state})"
  end
end
