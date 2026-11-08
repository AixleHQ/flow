# frozen_string_literal: true

require "test_helper"

module Sessions
  module Checks
    # The no-output watchdog's tests (task #208), carried over onto the snapshot: the same
    # verdicts, messages and skips, read through Sessions::Monitor.
    class NoOutputTest < ActiveSupport::TestCase
      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        @runtime = stub_container_runtime
        @session = create(:terminal_session, user: @user, project: @project, container_id: "ctr-abc",
                                             started_at: 2.hours.ago, session_type: "workflow_step",
                                             state: "ready", mode: "non_interactive", initial_prompt: "do the work")
        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
      end

      teardown do
        cleanup_runtime_overrides
      end

      def kiro_pane(name) = file_fixture("terminal_panes/kiro_cli/#{name}.txt").read

      # One pass over the session with only this check. @return [Symbol, nil] its outcome
      def pass(text, last_output_at:)
        @runtime.set_terminal_pane(text, last_output_at: last_output_at)
        Monitor.new(checks: [ NoOutput ]).visit(@session.reload).last&.outcome
      end

      # What the token-refresh sweep asks, on an on-demand snapshot; its read feeds the
      # same record as the passes'.
      def silent_for?(duration, text, last_output_at:)
        @runtime.set_terminal_pane(text, last_output_at: last_output_at)
        session = @session.reload
        kept = KeptState.new(session)
        snapshot = Monitor.snapshot(session, parts: NoOutput.parts, runtime: @runtime)
        silent = NoOutput.new(session, runtime: @runtime, kept: kept.for(NoOutput)).silent_for?(snapshot, duration)
        kept.write!
        silent
      end

      test "fails a session whose last output is older than the threshold" do
        assert_equal :failed, pass("some output", last_output_at: 45.minutes.ago)

        @session.reload
        assert_equal "failed", @session.state
        assert_match(/no output for 30 minutes/i, @session.error_message)
        assert_match(/blocked on an interactive prompt/, @session.error_message)
      end

      test "leaves a session whose last output is within the threshold" do
        assert_nil pass("recent output", last_output_at: 5.minutes.ago)
        assert_equal "ready", @session.reload.state
      end

      test "leaves a session whose log has no mtime yet" do
        assert_nil pass("", last_output_at: nil)
        assert_equal "ready", @session.reload.state
      end

      test "leaves a session whose pane could not be captured, however old its log" do
        @runtime.fail_exec("capture-pane")

        assert_nil pass("", last_output_at: 45.minutes.ago)
        assert_equal "ready", @session.reload.state
      end

      test "leaves a session whose container is gone to the dead-container watchdog" do
        @runtime.set_terminal_pane("", last_output_at: 45.minutes.ago)
        @runtime.unreachable_on_exec("capture-pane")

        result = Monitor.new(checks: [ NoOutput ]).pass

        assert_equal 1, result[:unreachable]
        assert_equal "ready", @session.reload.state
      end

      test "names an expired login when the pane still shows its banner" do
        pass("> /login\nLogin expired · Please run /login\n", last_output_at: 40.minutes.ago)

        assert_match(/agent authentication failed — .*Login expired/, @session.reload.error_message)
      end

      test "says the agent stopped without finish_session when the pane shows its idle prompt" do
        @session.update!(agent_type: "kiro_cli")

        assert_equal :failed, pass(kiro_pane("turn_ended_provider_error"), last_output_at: 40.minutes.ago)

        assert_match(/ended its turn without calling `finish_session`/, @session.reload.error_message)
        assert_match(/30 minutes/, @session.error_message)
      end

      # Task #208, case 1: an idle Kiro repaints its unchanged screen, so the log keeps
      # getting bytes while nothing happens.
      test "a Kiro screen unchanged for 30 minutes is silent even while bytes keep arriving" do
        @session.update!(agent_type: "kiro_cli")
        assert_nil pass(kiro_pane("turn_ended"), last_output_at: Time.current)
        travel 20.minutes
        assert_nil pass(kiro_pane("turn_ended"), last_output_at: 5.seconds.ago)
        travel 11.minutes

        assert_equal :failed, pass(kiro_pane("turn_ended"), last_output_at: 2.seconds.ago)
      end

      test "a working Kiro session's changing screen keeps it alive" do
        @session.update!(agent_type: "kiro_cli")
        working = kiro_pane("working")
        pass(working, last_output_at: Time.current)
        travel 31.minutes

        assert_nil pass(working.sub("Kiro is working · 6s", "Kiro is working · 31m 6s"), last_output_at: 1.second.ago)
      end

      test "a first read judges by the last byte, as before" do
        @session.update!(agent_type: "kiro_cli")

        assert_equal :failed, pass("some output", last_output_at: 45.minutes.ago)
      end

      test "keeps the screen's record in the session's metadata" do
        @session.update!(agent_type: "kiro_cli")
        pass(kiro_pane("turn_ended"), last_output_at: 3.seconds.ago)

        metadata = @session.reload.metadata
        assert_equal ScreenDigest.of(kiro_pane("turn_ended")), metadata[NoOutput::SCREEN_KEY]
        assert_in_delta 3.seconds.ago, Time.zone.parse(metadata[NoOutput::SCREEN_CHANGED_AT_KEY]), 1.second
      end

      # Sessions read by the token-refresh sweep: a parked session's repaints no longer pass
      # for an agent mid-turn, and a ticking working indicator still does.
      test "a shorter silence asked by the token-refresh sweep follows the screen too" do
        @session.update!(agent_type: "kiro_cli")
        pass(kiro_pane("turn_ended"), last_output_at: Time.current)
        travel 11.minutes

        assert silent_for?(10.minutes, kiro_pane("turn_ended"), last_output_at: 1.second.ago)
        refute silent_for?(10.minutes, kiro_pane("working"), last_output_at: 1.second.ago)
      end

      # The screen rule is opt-in per runtime (SCREEN_RULE_RUNTIMES). A runtime whose working
      # screen has not been measured keeps the log-mtime rule, for the watchdog and for the
      # token-refresh sweep alike: an indicator that animates only through colour captures the
      # same on two reads while its agent works.
      test "a runtime outside the screen rule is judged by the log's last byte" do
        pane = "\u273B Thinking\u2026\n> \n"
        assert_nil pass(pane, last_output_at: Time.current)
        travel 31.minutes

        assert_nil pass(pane, last_output_at: 2.seconds.ago)
        refute silent_for?(10.minutes, pane, last_output_at: 2.seconds.ago)
        refute @session.reload.metadata.key?(NoOutput::SCREEN_KEY), "no screen record is kept"
      end

      test "a runtime outside the screen rule goes stale once its log stops getting bytes" do
        assert_equal :failed, pass("\u273B Thinking\u2026\n> \n", last_output_at: 31.minutes.ago)
      end

      test "only Kiro is judged by its screen for now" do
        assert NoOutput.screen_rule?("kiro_cli")
        %w[claude_code codex cursor_cli gemini_cli antigravity_cli grok].each do |agent_type|
          refute NoOutput.screen_rule?(agent_type), agent_type
        end
      end

      # Silence is what an interactive step looks like while its person reviews the work.
      test "an interactive step waiting on its person is left alone however quiet" do
        @session.update!(mode: "interactive")

        assert_nil pass("some output", last_output_at: 2.hours.ago)
        assert_empty @runtime.execs, "a session no check applies to is not read"
      end

      # Sessions::AuthPause bounds that wait itself; the watchdog would end it at 30 minutes.
      test "a step waiting for its agent's login to be renewed is left alone" do
        @session.merge_jsonb!(:metadata, "auth_paused_at" => 2.hours.ago.iso8601)

        assert_nil pass("some output", last_output_at: 2.hours.ago)
        assert_equal "ready", @session.reload.state
      end

      test "a step that started finishing while the pass read it is not failed" do
        @runtime.on_next_exec("capture-pane") { TerminalSession.find(@session.id).update!(state: "finishing") }

        assert_equal :taken_over, pass("some output", last_output_at: 45.minutes.ago)

        @session.reload
        assert_equal "finishing", @session.state
        assert_nil @session.error_message
      end
    end
  end
end
