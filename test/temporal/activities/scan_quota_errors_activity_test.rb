# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class ScanQuotaErrorsActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @runtime_mock = mock("runtime")
        ContainerRuntime.stubs(:build).returns(@runtime_mock)
        @runtime_mock.stubs(:resolve_container).returns(nil)
        @runtime_mock.stubs(:exec!).returns([ [], [], 0 ])

        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
        Rails.logger.stubs(:error)
      end

      # Joins pattern text that the source keeps split (see the task #195 tests below).
      def self.phrase(*parts) = parts.join

      KIRO_STOP = phrase("You have reached your mon", "thly usage lim", "it.")

      test "fails ready workflow_step session with quota error in error_message" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-abc",
          started_at: 3.minutes.ago,
          error_message: "Credit balance too low · Add funds: https://platform.claude.com/settings/billing")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_equal "Credit balance too low · Add funds: https://platform.claude.com/settings/billing",
                     session.error_message
      end

      test "fails ready session when quota error appears only in live terminal output" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-live",
          started_at: 3.minutes.ago,
          error_message: nil)

        stub_pane("container-live", [ "Credit balance too low · Add funds: https://platform.claude.com/settings/billing\n" ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_equal "Credit balance too low · Add funds: https://platform.claude.com/settings/billing",
                     session.error_message
      end

      test "stores short error_message when terminal capture includes shell prompt noise" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-noisy",
          started_at: 3.minutes.ago,
          error_message: nil)

        stub_pane("container-noisy", [
          "claude@d683c38e063a:/workspace$",
          "claude \"$AGENT_PROMPT\"",
          "Credit balance too low · Add funds: https://platform.claude.com/settings/billing"
        ])

        run_activity(ScanQuotaErrorsActivity)

        session.reload
        assert_equal "Credit balance too low · Add funds: https://platform.claude.com/settings/billing",
                     session.error_message
      end

      test "fails ready cursor_cli session with usage limit in terminal output" do
        session = create(:terminal_session,
          user: @user,
          agent_type: "cursor_cli",
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-cursor",
          started_at: 3.minutes.ago,
          error_message: nil)

        stub_pane("container-cursor", [
          "Error: You've reached your normal usage limit.\n",
          "You're out of usage. Ask your admin to increase your limit to continue.\n"
        ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_equal "Error: You've reached your normal usage limit.", session.error_message
      end

      test "signals the failed session's own container workflow so its cleanup runs" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-quota",
          started_at: 3.minutes.ago,
          temporal_workflow_id: "wf-quota",
          error_message: "Credit balance too low · Add funds: https://platform.claude.com/settings/billing")

        # Failing the row alone left this execution parked on its `container_finished`
        # await for 23 hours, so the pod, Service and IngressRoute were never
        # reclaimed. It is the same leak the dead-container watchdog had to avoid.
        TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        assert_equal "failed", session.reload.state
      end

      test "skips a session whose container is unreachable instead of scanning it" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-gone",
          started_at: 3.minutes.ago,
          error_message: nil)

        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with("container-gone").returns(container)
        @runtime_mock.stubs(:exec!).raises(
          ContainerRuntime::ContainerUnreachableError.new(
            status_code: 404, container_identifier: "aixle/terminal-gone"
          )
        )

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        assert_equal 1, result[:unreachable]
        session.reload
        assert_equal "ready", session.state
        assert_nil session.error_message
      end

      test "still fails a session when the command runs and merely exits non-zero" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          state: "ready",
          container_id: "container-busy",
          started_at: 3.minutes.ago,
          error_message: "Credit balance too low")

        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with("container-busy").returns(container)
        @runtime_mock.stubs(:exec!).returns([ [], [ "no server running on /tmp/tmux-0/default\n" ], 1 ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        assert_equal 0, result[:unreachable]
        session.reload
        assert_equal "failed", session.state
      end

      test "does not touch sessions without quota error text" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :workflow_step,
          started_at: 3.minutes.ago,
          error_message: "Connection refused")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "does not touch sessions younger than MIN_AGE" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :workflow_step,
          started_at: 30.seconds.ago,
          error_message: "Credit balance too low")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "does not touch sessions without container_id" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :workflow_step,
          container_id: nil,
          started_at: 3.minutes.ago,
          error_message: "Credit balance too low")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "does not touch non-workflow_step sessions" do
        session = create(:terminal_session, :running,
          user: @user,
          session_type: :agent_session,
          started_at: 3.minutes.ago,
          error_message: "insufficient_quota")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "running", session.state
      end

      test "returns cleaned count of 0 when no candidate sessions exist" do
        result = run_activity(ScanQuotaErrorsActivity)
        assert_equal 0, result[:cleaned]
      end

      # ===================================================================
      # Unanswerable startup prompts (task #605)
      #
      # A non_interactive step parked on a TTY dialog never errors and never
      # finishes: it stays `ready` on zero tokens until a human notices. The
      # no-output watchdog only reaches it after 30 minutes of silence, and its
      # message names the wrong cause; this sweep already reads the pane every
      # minute, so the dialog is caught here instead.
      # ===================================================================

      test "fails a non_interactive session parked on the Codex workspace-trust prompt" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          agent_type: "codex",
          mode: "non_interactive",
          initial_prompt: "Fix the failing tests",
          state: "ready",
          container_id: "container-trust",
          started_at: 3.minutes.ago,
          error_message: nil)

        stub_trust_prompt_pane("container-trust")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_match(/workspace-trust prompt/, session.error_message)
      end

      test "leaves an interactive session on the trust prompt for its owner to answer" do
        session = create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          agent_type: "codex",
          mode: "interactive",
          state: "ready",
          container_id: "container-trust-interactive",
          started_at: 3.minutes.ago,
          error_message: nil)

        stub_trust_prompt_pane("container-trust-interactive")

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "ready", session.state
      end

      # ===================================================================
      # The agent's own work on screen is not a quota stop (task #195)
      #
      # Run 42797 / session 45714: a Kiro session grepped app/frontend for
      # failureReason, the scan matched OpenAI's identifier in one line of the
      # output, and failed a session that was working normally. The pattern text in
      # these tests is split with `phrase` so this file never matches a pattern
      # itself when an agent reads or greps it.
      # ===================================================================

      test "keeps a Kiro session working whose grep output shows another provider's identifier" do
        session = create_step_session(agent_type: "kiro_cli", container_id: "container-kiro-grep")
        stub_pane("container-kiro-grep", [
          "● Reading file: app/frontend/pages/Projects/WorkflowRuns/ShowPage.tsx\n",
          "> grep -rn \"failureReason\" app/frontend --include=*.tsx\n",
          "app/frontend/pages/Projects/WorkflowRuns/ShowPage.tsx:441:        <section>\n",
          phrase("app/frontend/pages/Projects/WorkflowRuns/ShowPage.tsx:442:        {run.failureReason === 'quo", "ta_exc", "eeded' && (\n"),
          "app/frontend/pages/Projects/WorkflowRuns/ShowPage.tsx:443:          <QuotaBanner run={run} />\n",
          "\n",
          "● Thinking...\n"
        ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        session.reload
        assert_equal "ready", session.state
        assert_nil session.error_message
      end

      test "keeps a session working whose tool output shows other providers' identifiers" do
        session = create_step_session(agent_type: "codex", container_id: "container-codex-grep")
        stub_pane("container-codex-grep", [
          "$ rg -n 'EXHAUSTED|insufficient' app/services\n",
          phrase("app/services/quota_error_detector.rb:18:      /RESOURCE_EXH", "AUSTED/i,\n"),
          phrase("app/services/quota_error_detector.rb:9:      /insufficient_qu", "ota/i,\n"),
          phrase("test/services/quota_error_detector_test.rb:120:    error = '{\"status\": \"RESOURCE_EXH", "AUSTED\"}'\n"),
          "› Working (12s • esc to interrupt)\n"
        ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        assert_equal "ready", session.reload.state
      end

      test "keeps a session working whose own provider's message is only in the scrollback" do
        session = create_step_session(agent_type: "kiro_cli", container_id: "container-kiro-scrollback")
        stub_pane("container-kiro-scrollback", [
          phrase("test/services/quota_error_detector_test.rb:256:   \"You have reached your mon", "thly usage lim", "it.\"\n"),
          *Array.new(QuotaErrorDetector::TAIL_LINES) { |i| "test #{i} passed\n" }
        ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        assert_equal "ready", session.reload.state
      end

      test "does not fail a session for its own quota message while the pane is still producing output" do
        session = create_step_session(agent_type: "kiro_cli", container_id: "container-kiro-busy")
        stub_pane("container-kiro-busy", [ "#{KIRO_STOP}\n" ], last_output_at: 10.seconds.ago)

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        assert_equal "ready", session.reload.state
      end

      test "does not fail a session for its own quota message when the pane's last output time is unknown" do
        session = create_step_session(agent_type: "kiro_cli", container_id: "container-kiro-unknown")
        stub_pane("container-kiro-unknown", [ "#{KIRO_STOP}\n" ], last_output_at: nil)

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        assert_equal "ready", session.reload.state
      end

      test "fails a session whose own CLI stopped on its quota message and went quiet" do
        session = create_step_session(agent_type: "kiro_cli", container_id: "container-kiro-quiet")
        stub_pane("container-kiro-quiet", [ "● Thinking...\n", "#{KIRO_STOP}\n", "\n", "\n" ], last_output_at: 2.minutes.ago)

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 1, result[:cleaned]
        session.reload
        assert_equal "failed", session.state
        assert_equal KIRO_STOP, session.error_message
        # What CompleteStepActivity reads to fail the step for quota, pause the run and
        # record the credential.
        assert_predicate QuotaErrorDetector.detect(session.error_message), :quota_error?
      end

      # Each agent's own rendered quota message, from QuotaErrorDetector::PATTERNS.
      OWN_QUOTA_STOPS = {
        "claude_code" => phrase("Credit bal", "ance too low · Add funds: https://platform.cl", "aude.com/settings/billing"),
        "codex" => phrase("ERROR: You exc", "eeded your current quo", "ta, please check your plan and billing details."),
        "gemini_cli" => phrase("Usage lim", "it reached for all Pro models."),
        "antigravity_cli" => phrase("AI credits bal", "ance is too low. Top up to continue."),
        "cursor_cli" => phrase("Error: You've reached your normal usa", "ge limit."),
        "grok" => phrase("You're out of cre", "dits."),
        "kiro_cli" => phrase("You have reached your mon", "thly usage lim", "it.")
      }.freeze

      OWN_QUOTA_STOPS.each do |agent_type, message|
        test "fails a #{agent_type} session that stopped on its own quota message" do
          container_id = "container-own-#{agent_type}"
          session = create_step_session(agent_type: agent_type, container_id: container_id)
          stub_pane(container_id, [ "● Working on the task\n", "#{message}\n" ])

          result = run_activity(ScanQuotaErrorsActivity)

          assert_equal 1, result[:cleaned]
          session.reload
          assert_equal "failed", session.state
          assert_equal message, session.error_message
        end
      end

      test "covers every agent type with an own quota stop" do
        assert_equal AgentCredentialsService::ADAPTERS.keys.sort, OWN_QUOTA_STOPS.keys.sort
      end

      test "does not fail a session for another provider's quota message, even on a quiet screen" do
        session = create_step_session(agent_type: "kiro_cli", container_id: "container-kiro-foreign")
        stub_pane("container-kiro-foreign", [ "#{OWN_QUOTA_STOPS.fetch('claude_code')}\n" ])

        result = run_activity(ScanQuotaErrorsActivity)

        assert_equal 0, result[:cleaned]
        assert_equal "ready", session.reload.state
      end

      private

      def phrase(*parts) = self.class.phrase(*parts)

      def create_step_session(agent_type:, container_id:)
        create(:terminal_session,
          user: @user,
          session_type: :workflow_step,
          agent_type: agent_type,
          mode: "non_interactive",
          initial_prompt: "Fix the failing tests",
          state: "ready",
          container_id: container_id,
          started_at: 3.minutes.ago,
          error_message: nil)
      end

      # The pane the sweep captures, and the pipe-pane log's mtime that
      # Sessions::LiveLogReader reads once a quota error is on screen: a pane counts
      # only once it has been quiet for QuotaErrorDetector::QUIET_BEFORE_FAIL.
      def stub_pane(container_id, lines, last_output_at: 5.minutes.ago)
        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with(container_id).returns(container)
        @runtime_mock.stubs(:exec!).returns([ lines, [], 0 ])
        mtime = last_output_at ? "#{last_output_at.to_i}\n" : ""
        @runtime_mock.stubs(:exec!).with { |_container, cmd, *| cmd.last.start_with?("stat ") }
                     .returns([ [ "#{mtime}#{Sessions::LiveLogReader::MARKER}\n", *lines ], [], 0 ])
      end

      def stub_trust_prompt_pane(container_id)
        container = mock("container")
        @runtime_mock.stubs(:resolve_container).with(container_id).returns(container)
        @runtime_mock.stubs(:exec!).returns([
          [ "  Folder access\n",
            "  /workspace\n",
            "  Trust this folder? Codex can read, edit, and run files here, subject to your\n",
            "› 1. Trust and continue\n",
            "  2. Quit\n",
            "  enter continue · esc quit\n" ],
          [],
          0
        ])
      end
    end
  end
end
