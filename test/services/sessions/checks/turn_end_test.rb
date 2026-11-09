# frozen_string_literal: true

require "test_helper"

module Sessions
  module Checks
    class TurnEndTest < ActiveSupport::TestCase
      REMINDER = PaneInput.command(TurnEnd::MESSAGE).freeze

      setup do
        @user = create(:user, :with_company)
        @project = create(:project, owner: @user, company: @user.companies.first)
        @runtime = stub_container_runtime(agent_type: "kiro_cli")
        @session = create(:terminal_session, session_type: "workflow_step", state: "ready", mode: "non_interactive",
                                             agent_type: "kiro_cli", user: @user, project: @project,
                                             container_id: "ctr-kiro", started_at: 1.hour.ago, initial_prompt: "do the work")
        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
      end

      teardown do
        cleanup_runtime_overrides
      end

      def pane(name) = file_fixture("terminal_panes/kiro_cli/#{name}.txt").read

      # One pass of the monitor over this session, with only this check, on a pane showing
      # `text`. @return [Symbol, nil] the check's outcome
      def observe(session, text)
        @runtime.set_terminal_pane(text)
        Monitor.new(checks: [ TurnEnd ]).visit(session).last&.outcome
      end

      # The once-a-minute pass reading the same pane twice.
      def observe_twice(text)
        observe(@session, text)
        travel 1.minute
        observe(@session.reload, text)
      end

      def reminders
        @runtime.execs.count(REMINDER)
      end

      test "a turn end seen once is only remembered" do
        assert_equal :pending, observe(@session, pane("turn_ended"))
        assert_equal 0, reminders
      end

      test "a turn end on two reads gets one reminder, and the agent is sent back to work" do
        assert_equal :nudged, observe_twice(pane("turn_ended"))

        assert_equal 1, reminders
        assert_equal 1, @session.reload.metadata[TurnEnd::COUNT_KEY]
        assert_equal "ready", @session.state
      end

      test "a turn ended by a provider error gets the reminder too" do
        assert_equal :nudged, observe_twice(pane("turn_ended_provider_error"))
      end

      test "a screen that changed between the two reads starts over" do
        observe(@session, pane("turn_ended"))
        travel 1.minute

        assert_equal :pending, observe(@session.reload, pane("turn_ended_after_nudge"))
        assert_equal 0, reminders
      end

      test "a working agent is left alone and its remembered turn end forgotten" do
        observe(@session, pane("turn_ended"))

        assert_nil observe(@session.reload, pane("working"))
        refute @session.reload.metadata.key?(TurnEnd::SCREEN_KEY)
      end

      test "a person who typed in the terminal within ten minutes is not interrupted" do
        @runtime.set_terminal_clients([ [ false, 5.minutes.ago ] ])

        assert_equal :pending, observe_twice(pane("turn_ended"))
        assert_equal 0, reminders
      end

      test "the reminders resume ten minutes after the person's last input" do
        @runtime.set_terminal_clients([ [ false, 5.minutes.ago ] ])
        observe_twice(pane("turn_ended"))
        travel 2.minutes
        @runtime.set_terminal_clients([ [ false, 12.minutes.ago ] ])

        assert_equal :nudged, observe(@session.reload, pane("turn_ended"))
      end

      test "watching from a read-only terminal does not hold the reminder" do
        @runtime.set_terminal_clients([ [ true, 1.minute.ago ] ])

        assert_equal :nudged, observe_twice(pane("turn_ended"))
      end

      test "terminal clients that cannot be read hold the reminder" do
        @runtime.fail_exec("list-clients")

        assert_equal :pending, observe_twice(pane("turn_ended"))
        assert_equal 0, reminders
      end

      # The reminder is counted, and the confirmed screen forgotten, before it is typed: a
      # Temporal retry of a scan that was cut off after tmux took the keys finds nothing
      # confirmed and types nothing.
      test "an interruption after the keys were sent does not send the reminder again" do
        @runtime.raise_on_exec("send-keys", error: Timeout::Error.new("worker cut off"))

        assert_equal :pending, observe_twice(pane("turn_ended"))
        assert_equal 1, reminders, "tmux was handed the reminder once"
        assert_equal 1, @session.reload.metadata[TurnEnd::COUNT_KEY]

        assert_equal :pending, observe(@session.reload, pane("turn_ended"))
        assert_equal 1, reminders
      end

      test "two scans that confirmed the same screen send one reminder" do
        observe(@session, pane("turn_ended"))
        travel 1.minute
        first = TerminalSession.find(@session.id)
        second = TerminalSession.find(@session.id)

        assert_equal :nudged, observe(first, pane("turn_ended"))
        assert_equal :pending, observe(second, pane("turn_ended"))

        assert_equal 1, reminders
        assert_equal 1, @session.reload.metadata[TurnEnd::COUNT_KEY]
      end

      test "a reminder that could not be typed still counts toward the limit" do
        @runtime.fail_exec("send-keys", times: 1)

        assert_equal :pending, observe_twice(pane("turn_ended"))
        assert_equal 1, @session.reload.metadata[TurnEnd::COUNT_KEY]

        travel 1.minute
        assert_equal :nudged, observe_twice(pane("turn_ended"))
        assert_equal 2, @session.reload.metadata[TurnEnd::COUNT_KEY]
      end

      test "the turn end after the last reminder fails the session with a clear message" do
        @session.merge_jsonb!(:metadata, TurnEnd::COUNT_KEY => TurnEnd::LIMIT)

        assert_equal :failed, observe_twice(pane("turn_ended"))

        assert_equal 0, reminders
        @session.reload
        assert_equal "failed", @session.state
        assert_match(/ended its turn without calling `finish_session` 4 times/, @session.error_message)
        assert_match(/3 reminders/, @session.error_message)
      end

      # The pass loads its sessions up front and reads one pane at a time, so the copy it
      # hands over can be seconds old. Another process changes the row in between.
      def give_up_on_a_stale_copy
        @session.merge_jsonb!(:metadata, TurnEnd::COUNT_KEY => TurnEnd::LIMIT)
        observe(@session, pane("turn_ended"))
        travel 1.minute
        scan_copy = TerminalSession.find(@session.id)
        yield TerminalSession.find(@session.id)

        observe(scan_copy, pane("turn_ended"))
      end

      test "a session that started finishing after the scan read it is not failed at the limit" do
        result = give_up_on_a_stale_copy { |other| other.update!(state: "finishing") }

        assert_equal :taken_over, result
        @session.reload
        assert_equal "finishing", @session.state
        assert_nil @session.error_message
      end

      test "a session auth-paused after the scan read it is not failed at the limit" do
        result = give_up_on_a_stale_copy { |other| other.merge_jsonb!(:metadata, "auth_paused_at" => Time.current.iso8601) }

        assert_equal :taken_over, result
        @session.reload
        assert_equal "ready", @session.state
        assert_nil @session.error_message
      end

      # A newer observer saw the agent working and forgot the confirmed turn end.
      test "a session whose confirmation was cleared after the scan read it is not failed at the limit" do
        result = give_up_on_a_stale_copy { |other| other.remove_jsonb_keys!(:metadata, TurnEnd::SCREEN_KEY, TurnEnd::SEEN_AT_KEY) }

        assert_equal :taken_over, result
        @session.reload
        assert_equal "ready", @session.state
        assert_nil @session.error_message
      end

      # ...and then saw a turn end again, which is not confirmed yet: same screen, a later time.
      test "a session whose confirmation was replaced after the scan read it is not failed at the limit" do
        result = give_up_on_a_stale_copy do |other|
          other.merge_jsonb!(:metadata, TurnEnd::SEEN_AT_KEY => Time.current.iso8601)
        end

        assert_equal :taken_over, result
        @session.reload
        assert_equal "ready", @session.state
        assert_nil @session.error_message
      end

      test "every reminder counts toward the limit" do
        TurnEnd::LIMIT.times do |i|
          assert_equal :nudged, observe_twice(pane(i.even? ? "turn_ended" : "turn_ended_after_nudge"))
          travel 1.minute
        end

        assert_equal TurnEnd::LIMIT, reminders
        assert_equal :failed, observe_twice(pane("turn_ended"))
      end

      test "a session paused on an expired login is Sessions::AuthPause's" do
        @session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)

        assert_nil observe_twice(pane("turn_ended"))
        assert_equal 0, reminders
      end

      test "an interactive session is never typed into" do
        @session.update!(mode: "interactive")

        assert_nil observe_twice(pane("turn_ended"))
        assert_equal 0, reminders
      end

      test "a finishing session is left alone" do
        @session.update!(state: "finishing")

        assert_nil observe_twice(pane("turn_ended"))
        assert_equal 0, reminders
      end

      test "a session that is not a workflow step is left alone" do
        @session.update!(session_type: "agent_session")

        assert_nil observe_twice(pane("turn_ended"))
        assert_equal 0, reminders
      end
    end
  end
end
