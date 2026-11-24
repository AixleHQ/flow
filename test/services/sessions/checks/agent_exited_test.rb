# frozen_string_literal: true

require "test_helper"

module Sessions
  module Checks
    class AgentExitedTest < ActiveSupport::TestCase
      include SecretLeakAssertions

      # What tmux keeps of an 80-column pane whose Cursor CLI refused its model (task #324),
      # captured joined: the CLI's line whole, then tmux's own notice.
      CURSOR_REFUSAL = "Cannot use this model: composer-2.5[effort=low]. Available models: auto, gpt-5.3-codex-low, " \
                       "gpt-5.3-codex-low-fast, composer-2.5, composer-2.5-fast\n\n" \
                       "Pane is dead (status 1, Sat Nov 21 10:35:44 2026)\n"

      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        @runtime = stub_container_runtime
        @session = create(:terminal_session, user: @user, project: @project, container_id: "ctr-abc",
                                             started_at: 5.minutes.ago, session_type: "workflow_step",
                                             state: "ready", mode: "non_interactive", agent_type: "cursor_cli",
                                             initial_prompt: "do the work")
        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
      end

      teardown do
        cleanup_runtime_overrides
      end

      # One pass over the session with only this check. @return [Symbol, nil] its outcome
      def pass
        Monitor.new(checks: [ AgentExited ]).visit(@session.reload).last&.outcome
      end

      test "fails a step whose CLI exited, with its status and its own words" do
        @runtime.set_agent_exit(1, pane: CURSOR_REFUSAL)

        assert_equal :failed, pass

        @session.reload
        assert_equal "failed", @session.state
        assert_equal "Session terminated: the agent CLI exited with status 1 without calling `finish_session`. " \
                     "Its last output: Cannot use this model: composer-2.5[effort=low]. Available models: auto, " \
                     "gpt-5.3-codex-low, gpt-5.3-codex-low-fast, composer-2.5, composer-2.5-fast",
                     @session.error_message
      end

      test "a CLI that exits cleanly without finishing the step fails it too" do
        @runtime.set_agent_exit(0)

        assert_equal :failed, pass
        assert_equal "Session terminated: the agent CLI exited with status 0 without calling `finish_session`.",
                     @session.reload.error_message
      end

      # tmux gives a process that died of a signal no status, only `pane_dead_signal`.
      test "a CLI killed by a signal fails the step, naming the signal" do
        @runtime.set_agent_exit(nil, signal: 9, pane: "working...\n\nPane is dead (signal 9, Sat Nov 21 17:20:55 2026)\n")

        assert_equal :failed, pass
        assert_equal "Session terminated: the agent CLI was killed by signal 9 without calling `finish_session`. " \
                     "Its last output: working...",
                     @session.reload.error_message
      end

      test "leaves a step whose CLI is still running" do
        @runtime.set_agent_exit(nil)

        assert_nil pass
        assert_equal "ready", @session.reload.state
      end

      test "leaves a step whose pane could not be read" do
        @runtime.fail_exec("display-message")

        assert_nil pass
        assert_equal "ready", @session.reload.state
      end

      test "the message is cut to its limit" do
        @runtime.set_agent_exit(1, pane: "#{'x' * 2000}\n")

        assert_equal :failed, pass
        assert_equal AgentExited::MAX_MESSAGE_LENGTH, @session.reload.error_message.length
      end

      test "an interactive step is left to the person who can start the CLI again" do
        @session.update!(mode: "interactive")

        assert_not AgentExited.applies_to?(@session)
      end

      test "a step that is finishing is not failed for its CLI exiting" do
        put_session_in_state!(@session, "finishing")

        assert_not AgentExited.applies_to?(@session)
      end

      test "a step younger than a minute is not read yet" do
        @session.update!(started_at: 10.seconds.ago)

        assert_not AgentExited.applies_to?(@session)
      end

      # The message reaches error_message, the step's error and the Slack failure notice.
      test "a secret in the CLI's output does not reach the failure message" do
        @session.config_items << create(:config_item, :secret, scope: @project, name: "PROJECT_X_API_KEY",
                                                              value: RECORDED_SECRET)
        @runtime.set_agent_exit(1, pane: "Error: invalid API key #{RECORDED_SECRET}\n")

        assert_equal :failed, pass

        message = @session.reload.error_message
        assert_match(/Its last output: Error: invalid API key/, message)
        assert_no_secret message
      end
    end
  end
end
