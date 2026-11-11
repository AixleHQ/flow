# frozen_string_literal: true

# One model call, as every runtime reports it once its adapter has normalized it —
# the canonical usage record (docs/design/insights-usage-export.md §3). Rows are
# materialized from usage_statistics.events_data by LlmCalls::Materializer and never
# change afterwards: `uid` is the call's identity outside Flow.
class LlmCall < ApplicationRecord
  SOURCES = %w[otlp_log otlp_metric otlp_span otlp_credits mitm vendor_api cli_result].freeze
  GRANULARITIES = %w[request turn batch session].freeze
  # reported: the vendor or CLI said what it cost; priced: an estimate from list prices
  # (LlmCalls::Pricing), not a bill; credits: a credit charge converted at the configured
  # rate; unknown: no cost.
  COST_BASES = %w[reported priced credits unknown].freeze

  belongs_to :terminal_session
  belongs_to :workflow_run, optional: true
  belongs_to :step_run, optional: true

  validates :model, :provider, :occurred_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :granularity, inclusion: { in: GRANULARITIES }
  validates :cost_basis, inclusion: { in: COST_BASES }
  validates :total_cents_precise, absence: true, if: -> { cost_basis == "unknown" }

  scope :for_workflow_run, ->(id) { where(workflow_run_id: id) }
  scope :for_session, ->(id) { where(terminal_session_id: id) }
end
