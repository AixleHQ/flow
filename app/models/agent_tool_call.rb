# frozen_string_literal: true

# A tool an agent called — name, arguments, outcome, duration; never its output. Kept only
# for projects that share prompts with Aixle Insights (docs/design/insights-usage-export.md
# §3a). Written once by AgentActivity::Recorder, arguments masked and size-capped.
class AgentToolCall < ApplicationRecord
  SOURCES = %w[otlp_log transcript].freeze

  belongs_to :terminal_session
  belongs_to :workflow_run, optional: true
  belongs_to :step_run, optional: true

  validates :source, inclusion: { in: SOURCES }
  validates :source_key, :occurred_at, :tool_name, presence: true
end
