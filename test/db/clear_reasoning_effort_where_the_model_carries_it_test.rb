# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261121100000_clear_reasoning_effort_where_the_model_carries_it")

class ClearReasoningEffortWhereTheModelCarriesItTest < ActiveSupport::TestCase
  test "clears the level on Cursor and Antigravity steps and leaves other runtimes' levels alone" do
    cursor = create(:step, required_agent_runtime: "cursor_cli", preferred_model: "composer-2.5")
    cursor.update_columns(reasoning_effort: "low")
    antigravity = create(:step, required_agent_runtime: "antigravity_cli", preferred_model: "claude-sonnet-4-6")
    antigravity.update_columns(reasoning_effort: "high")
    claude = create(:step, required_agent_runtime: "claude_code", preferred_model: "claude-opus-5",
                           reasoning_effort: "high")

    migration = ClearReasoningEffortWhereTheModelCarriesIt.new
    migration.suppress_messages { migration.up }

    assert_nil cursor.reload.reasoning_effort
    assert_nil antigravity.reload.reasoning_effort
    assert_equal "composer-2.5", cursor.preferred_model
    assert_equal "high", claude.reload.reasoning_effort
    assert_predicate cursor, :valid?
    assert_predicate antigravity, :valid?
  end
end
