# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class ScanNoOutputSessionsActivityTest < ActiveSupport::TestCase
      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        stub_container_runtime
        # The watchdog's own verdict is covered by no_output_watchdog_test; here every
        # pane reads as silent past the threshold.
        Sessions::NoOutputWatchdog.stubs(:new).returns(stub(stale?: true, message: "Session terminated: no output"))
      end

      teardown do
        cleanup_runtime_overrides
      end

      def ready_step_session(mode:)
        create(:terminal_session, session_type: "workflow_step", state: "ready", mode: mode, user: @user,
                                  project: @project, container_id: "ctr-#{SecureRandom.hex(3)}",
                                  started_at: 2.hours.ago, initial_prompt: "do the work")
      end

      test "a silent unattended step is failed" do
        session = ready_step_session(mode: "non_interactive")
        SessionService.expects(:fail_session).with(has_entries(session: session)).once

        run_activity(ScanNoOutputSessionsActivity, nil)
      end

      # Silence is what an interactive step looks like while its person reviews
      # the work; the quota scanner leaves these alone for the same reason.
      test "an interactive step waiting on its person is left alone however quiet" do
        ready_step_session(mode: "interactive")
        SessionService.expects(:fail_session).never

        run_activity(ScanNoOutputSessionsActivity, nil)
      end

      # Sessions::AuthPause bounds that wait itself; the watchdog would end it at 30 minutes.
      test "a step waiting for its agent's login to be renewed is left alone" do
        session = ready_step_session(mode: "non_interactive")
        session.merge_jsonb!(:metadata, "auth_paused_at" => 2.hours.ago.iso8601)
        SessionService.expects(:fail_session).never

        run_activity(ScanNoOutputSessionsActivity, nil)
      end
    end

    # The watchdog for real, at the schedule's 5-minute cadence, on a Kiro session that has
    # no screen record yet (task #208, case 1): its screen stands still from the start while
    # repaints keep the log's mtime fresh.
    class ScanNoOutputSessionsScreenTest < ActiveSupport::TestCase
      SWEEP_EVERY = 5.minutes

      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        @runtime = stub_container_runtime(agent_type: "kiro_cli")
        @session = create(:terminal_session, session_type: "workflow_step", state: "ready", mode: "non_interactive",
                                             agent_type: "kiro_cli", user: @user, project: @project,
                                             container_id: "ctr-kiro", started_at: Time.current,
                                             initial_prompt: "do the work")
        @pane = file_fixture("terminal_panes/kiro_cli/turn_ended.txt").read
        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
      end

      teardown do
        cleanup_runtime_overrides
      end

      def sweep
        @runtime.set_terminal_pane(@pane, last_output_at: 2.seconds.ago)
        run_activity(ScanNoOutputSessionsActivity, nil)
      end

      test "an unchanged screen is ended 30 minutes after it stopped changing, not after a first read at minute 31" do
        sweep
        stopped_at = Time.zone.parse(@session.reload.metadata["screen_changed_at"])
        assert_in_delta 2.seconds.ago, stopped_at, 2.seconds, "the first sweep, at the session's start, starts the record"

        until @session.reload.state == "failed"
          travel SWEEP_EVERY
          sweep
          flunk "still alive #{(Time.current - stopped_at).round / 60} minutes later" if Time.current - stopped_at > 35.minutes
        end

        elapsed = Time.current - stopped_at
        assert_operator elapsed, :>=, Sessions::NoOutputWatchdog::NO_OUTPUT_THRESHOLD
        assert_operator elapsed, :<=, Sessions::NoOutputWatchdog::NO_OUTPUT_THRESHOLD + SWEEP_EVERY
        assert_match(/ended its turn without calling `finish_session`/, @session.error_message)
      end
    end
  end
end
