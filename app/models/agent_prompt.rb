# frozen_string_literal: true

# A prompt an agent received, kept only for projects that share prompts with Aixle
# Insights (docs/design/insights-usage-export.md §3a). Written once by
# AgentActivity::Recorder, masked and size-capped; `uid` is its id outside Flow.
class AgentPrompt < ApplicationRecord
  # otlp_log / transcript: the runtime reported it. flow: the session's initial prompt as
  # Flow rendered it, for a runtime that reports none.
  SOURCES = %w[otlp_log transcript flow].freeze

  belongs_to :terminal_session
  belongs_to :workflow_run, optional: true
  belongs_to :step_run, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :source_key, :occurred_at, :text_length, presence: true
end
