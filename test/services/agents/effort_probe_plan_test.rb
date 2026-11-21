# frozen_string_literal: true

require "test_helper"

module Agents
  class EffortProbePlanTest < ActiveSupport::TestCase
    def membership_offering(agent_type, models)
      stub(agent_models_for_props: [ { agent_type: agent_type, models: models, default_model: nil } ])
    end

    test "lists each offered model with each of its levels, as the adapter launches it" do
      membership = membership_offering("kiro_cli", [
        { model_id: "claude-sonnet-4.6", reasoning_effort_levels: %w[low max] },
        { model_id: "auto", reasoning_effort_levels: [] }
      ])

      rows = EffortProbePlan.for(membership, :kiro_cli)

      assert_equal [ %w[claude-sonnet-4.6 low], %w[claude-sonnet-4.6 max] ], rows.map { |row| row.values_at(:model, :effort) }
      assert_equal "kiro-cli --v3 chat --trust-all-tools --trust-workspace --model claude-sonnet-4.6 --effort low",
                   rows.first[:command]
      assert rows.all? { |row| row[:on_command_line] }
    end

    test "a level that is not on the command line is marked, so the probe skips it" do
      membership = membership_offering("gemini_cli", [ { model_id: "gemini-3-pro", reasoning_effort_levels: %w[low high] } ])

      rows = EffortProbePlan.for(membership, "gemini_cli")

      assert_equal 2, rows.size
      assert rows.none? { |row| row[:on_command_line] }
    end

    test "plain adds each model's launch without a level, where the model id carries the effort" do
      membership = membership_offering("antigravity_cli", [ { model_id: "gemini-3.8-flash-low", reasoning_effort_levels: [] } ])

      rows = EffortProbePlan.for(membership, "antigravity_cli", plain: true)

      assert_equal [ [ "gemini-3.8-flash-low", nil, true ] ], rows.map { |row| row.values_at(:model, :effort, :on_command_line) }
      assert rows.first[:command].end_with?("agy --model gemini-3.8-flash-low --dangerously-skip-permissions -i")
      assert_empty EffortProbePlan.for(membership, "antigravity_cli")
    end

    test "a runtime the member has no credential for has nothing to probe" do
      assert_empty EffortProbePlan.for(membership_offering("kiro_cli", []), "codex")
    end
  end
end
