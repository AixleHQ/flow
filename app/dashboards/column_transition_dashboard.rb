# frozen_string_literal: true

require "administrate/base_dashboard"

class ColumnTransitionDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    board_task: Field::BelongsTo,
    from_column: Field::BelongsTo.with_options(class_name: "BoardColumn", optional: true),
    to_column: Field::BelongsTo.with_options(class_name: "BoardColumn"),
    actor: Field::BelongsTo.with_options(class_name: "User"),
    workflow_run: Field::BelongsTo.with_options(optional: true),
    actor_type: Field::Select.with_options(
      include_blank: false,
      collection: %w[human agent auto_trigger]
    ),
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    board_task
    from_column
    to_column
    actor_type
    actor
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    board_task
    from_column
    to_column
    actor
    workflow_run
    actor_type
    created_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(transition)
    "##{transition.id}"
  end
end
