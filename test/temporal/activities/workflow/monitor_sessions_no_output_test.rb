# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    # The no-output check for real, at the pass's 1-minute cadence, on a Kiro session that has
    # no screen record yet (task #208, case 1): its screen stands still from the start while
    # repaints keep the log's mtime fresh. The check itself is covered in
    # test/services/sessions/checks/no_output_test.rb.
    class MonitorSessionsNoOutputTest < ActiveSupport::TestCase
      PASS_EVERY = 1.minute

      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        @runtime = stub_container_runtime(agent_type: "kiro_cli")
        @session = create(:terminal_session, session_type: "workflow_step", state: "ready", mode: "non_interactive",
                                             agent_type: "kiro_cli", user: @user, project: @project,
                                             container_id: "ctr-kiro", started_at: Time.current,
                                             initial_prompt: "do the work")
        # A screen frozen mid-turn: no turn end for Checks::TurnEnd to remind.
        @pane = file_fixture("terminal_panes/kiro_cli/working.txt").read
        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
      end

      teardown do
        cleanup_runtime_overrides
      end

      def pass
        @runtime.set_terminal_pane(@pane, last_output_at: 2.seconds.ago)
        run_activity(MonitorSessionsActivity, nil)
      end

      test "an unchanged screen is ended 30 minutes after it stopped changing, not after a first read at minute 31" do
        pass
        stopped_at = Time.zone.parse(@session.reload.metadata["screen_changed_at"])
        assert_in_delta 2.seconds.ago, stopped_at, 2.seconds, "the first pass, at the session's start, starts the record"

        until @session.reload.state == "failed"
          travel PASS_EVERY
          pass
          flunk "still alive #{(Time.current - stopped_at).round / 60} minutes later" if Time.current - stopped_at > 32.minutes
        end

        elapsed = Time.current - stopped_at
        assert_operator elapsed, :>=, Sessions::Checks::NoOutput::NO_OUTPUT_THRESHOLD
        assert_operator elapsed, :<=, Sessions::Checks::NoOutput::NO_OUTPUT_THRESHOLD + PASS_EVERY
        assert_match(/no output for 30 minutes/, @session.error_message)
      end

      test "one read per pass serves the no-output check and the quota scan's checks alike" do
        travel 2.minutes
        result = pass

        assert_equal 1, result[:read]
        assert_equal 1, @runtime.execs.size
      end
    end
  end
end
