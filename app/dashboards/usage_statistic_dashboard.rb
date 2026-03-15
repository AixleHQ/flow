# frozen_string_literal: true

require "administrate/base_dashboard"

class UsageStatisticDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number.with_options(searchable: true),
    terminal_session: Field::BelongsTo,
    source: Field::String,
    models: Field::String,
    tokens: Field::Number,
    input_tokens: Field::Number,
    output_tokens: Field::Number,
    cache_read_tokens: Field::Number,
    cache_write_tokens: Field::Number,
    cost_cents: Field::Number,
    total_cents_precise: Field::Number.with_options(decimals: 6),
    events_count: Field::Number,
    events_data: Field::JSONB,
    created_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M"),
    updated_at: Field::DateTime.with_options(format: "%b %-d, %Y %H:%M")
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    terminal_session
    source
    tokens
    cost_cents
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    terminal_session
    source
    models
    tokens
    input_tokens
    output_tokens
    cache_read_tokens
    cache_write_tokens
    cost_cents
    total_cents_precise
    events_count
    events_data
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(stat)
    "##{stat.id} (#{stat.source})"
  end
end
