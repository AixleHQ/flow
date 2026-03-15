# frozen_string_literal: true

require "administrate/base_dashboard"

class ColumnWorkflowBindingDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board_column: Field::BelongsTo,
    workflow: Field::BelongsTo,
    trigger_mode: Field::Select.with_options(
      include_blank: false,
      collection: %w[auto manual]
    ),
    cooldown_seconds: Field::Number,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    board_column
    workflow
    trigger_mode
    cooldown_seconds
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    board_column
    workflow
    trigger_mode
    cooldown_seconds
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(binding)
    "##{binding.id} #{binding.trigger_mode}"
  end
end
