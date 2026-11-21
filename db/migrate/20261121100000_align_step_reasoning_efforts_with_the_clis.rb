# frozen_string_literal: true

# config/agent_runtimes.json now offers only the reasoning-effort levels each CLI takes for
# each model, as measured by bin/agent-effort-probe on 2026-11-21 (task #324). A step that
# kept a level the CLI does not take would fail validation on its next save and on its next
# run's session, so each such level becomes what the CLI ran instead.
#
# - Cursor CLI and Antigravity CLI take the effort only through the model id: a level made
#   Cursor exit and Antigravity quietly run its default model.
# - Claude Code and Kiro CLI lower a level a model lacks to `high`, and ignore it on a
#   model with none.
class AlignStepReasoningEffortsWithTheClis < ActiveRecord::Migration[8.1]
  # [runtime, model pattern (PostgreSQL regex), levels it replaces, the level it becomes]
  RULES = [
    [ "cursor_cli", ".", nil, nil ],
    [ "antigravity_cli", ".", nil, nil ],
    [ "claude_code", "^claude-(haiku|sonnet)-4-5", nil, nil ],
    [ "claude_code", "^claude-opus-4-5", %w[xhigh max], "high" ],
    [ "claude_code", "^claude-(sonnet|opus)-4-6", %w[xhigh], "high" ],
    [ "kiro_cli", '^(claude-opus-4\.5|claude-sonnet-4\.5|deepseek-3\.2|minimax-m2\.5|minimax-m2\.1|glm-5|qwen3-coder-next)$',
      nil, nil ],
    [ "kiro_cli", '^claude-(sonnet|opus)-4\.6$', %w[xhigh], "high" ],
    [ "kiro_cli", "^grok-", %w[max], "high" ]
  ].freeze

  def up
    RULES.each do |runtime, model, from, to|
      levels = from ? "reasoning_effort IN (#{from.map { |level| connection.quote(level) }.join(', ')})" : "reasoning_effort IS NOT NULL"
      execute "UPDATE steps SET reasoning_effort = #{connection.quote(to)} " \
              "WHERE required_agent_runtime = #{connection.quote(runtime)} " \
              "AND preferred_model ~ #{connection.quote(model)} AND #{levels}"
    end
  end

  def down; end
end
