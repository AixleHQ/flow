# frozen_string_literal: true

require "administrate/base_dashboard"

class BoardActivityDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board: Field::BelongsTo,
    board_task: Field::BelongsTo.with_options(optional: true),
    actor: Field::BelongsTo.with_options,
    # Sourced from the model so the filter list can't drift from the enum.
    event_type: Field::Select.with_options(
      include_blank: false,
      collection: BoardActivity.event_type.values.map(&:to_s)
    ),
    actor_type: Field::Select.with_options(
      include_blank: false,
      collection: %w[human agent system]
    ),
    metadata: Field::JSONB,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    board
    board_task
    event_type
    actor_type
    actor
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    board
    board_task
    actor
    event_type
    actor_type
    metadata
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(activity)
    "##{activity.id} #{activity.event_type}"
  end
end
