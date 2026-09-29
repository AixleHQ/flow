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
    end
  end
end
