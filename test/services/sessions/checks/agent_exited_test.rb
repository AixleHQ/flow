# frozen_string_literal: true

require "test_helper"

module Sessions
  module Checks
    class AgentExitedTest < ActiveSupport::TestCase
      include SecretLeakAssertions

      PROMPT = "root@terminal-0123456789abcdef:/workspace#"

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

      def cursor_rejected_pane = file_fixture("terminal_panes/cursor_cli/model_rejected.txt").read

      # One pass over the session with only this check. @return [Symbol, nil] its outcome
      def pass(text)
        @runtime.set_terminal_pane(text, last_output_at: 1.minute.ago)
        Monitor.new(checks: [ AgentExited ]).visit(@session.reload).last&.outcome
      end

      test "fails a step whose CLI refused its model, with the CLI's own words" do
        assert_equal :failed, pass(cursor_rejected_pane)

        @session.reload
        assert_equal "failed", @session.state
        assert @session.error_message.start_with?(
          "Session terminated: the agent CLI exited with status 1 without calling `finish_session`. " \
          "Its last output: Cannot use this model: composer-2.5[effort=low]. Available models: auto,"
        ), @session.error_message
        assert_operator @session.error_message.length, :<=, AgentExited::MAX_MESSAGE_LENGTH
      end

      test "leaves a step whose CLI is still running" do
        assert_nil pass("#{PROMPT} agent --force \"$(cat /tmp/.aixle-prompt)\"; echo \"[aixle] agent exited with status $?\"\n" \
                        "  Cursor Agent\n  → Plan, search, build anything\n")
        assert_equal "ready", @session.reload.state
      end

      test "an interactive step is left to the person who can start the CLI again" do
        @session.update!(mode: "interactive")

        assert_not AgentExited.applies_to?(@session)
      end

      test "a step that is finishing is not failed for its CLI exiting" do
        @session.update!(state: "finishing")

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
        pane = "#{PROMPT} agent; echo \"[aixle] agent exited with status $?\"\n" \
               "Error: invalid API key #{RECORDED_SECRET}\n[aixle] agent exited with status 1\n#{PROMPT}\n"

        assert_equal :failed, pass(pane)

        message = @session.reload.error_message
        assert_match(/Its last output: Error: invalid API key/, message)
        assert_no_secret message
      end
    end
  end
end
