# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    # The quota scan's one pane read per session also decides whether an automatic session's
    # agent ended its turn without `finish_session` (Sessions::TurnEndNudge, covered in its
    # own test). Here: that the scan asks, and counts what happened.
    class ScanQuotaErrorsTurnEndTest < ActiveSupport::TestCase
      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        @runtime = stub_container_runtime(agent_type: "kiro_cli")
        @session = create(:terminal_session, session_type: "workflow_step", state: "ready", mode: "non_interactive",
                                             agent_type: "kiro_cli", user: @user, project: @project,
                                             container_id: "ctr-kiro", started_at: 1.hour.ago, initial_prompt: "do the work")
        @runtime.set_terminal_pane(file_fixture("terminal_panes/kiro_cli/turn_ended.txt").read,
                                   last_output_at: 2.minutes.ago)
        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
      end

      teardown do
        cleanup_runtime_overrides
      end

      test "an agent that ended its turn is reminded on the second scan" do
        assert_equal 0, run_activity(ScanQuotaErrorsActivity)[:nudged]
        travel 1.minute

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:nudged]
        assert_equal 0, result[:cleaned]
        assert_includes @runtime.execs, [ "tmux", "send-keys", "-t", "agent", "-l", Sessions::TurnEndNudge::MESSAGE ]
        assert_equal "ready", @session.reload.state
      end

      test "an agent that stopped again after the last reminder is failed" do
        @session.merge_jsonb!(:metadata, Sessions::TurnEndNudge::COUNT_KEY => Sessions::TurnEndNudge::LIMIT)
        run_activity(ScanQuotaErrorsActivity)
        travel 1.minute

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        assert_equal "failed", @session.reload.state
        assert_equal Sessions::TurnEndNudge.message_after_limit, @session.error_message
      end
    end
  end
end
