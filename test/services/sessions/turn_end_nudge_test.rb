# frozen_string_literal: true

require "test_helper"

module Sessions
  class TurnEndNudgeTest < ActiveSupport::TestCase
    REMINDER = [ "tmux", "send-keys", "-t", "agent", "-l", TurnEndNudge::MESSAGE ].freeze

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

    # The once-a-minute scan reading the same pane twice.
    def observe_twice(text)
      TurnEndNudge.new(@session, runtime: @runtime).observe(text)
      travel 1.minute
      TurnEndNudge.new(@session.reload, runtime: @runtime).observe(text)
    end

    def reminders
      @runtime.execs.count(REMINDER)
    end

    test "a turn end seen once is only remembered" do
      assert_equal :pending, TurnEndNudge.new(@session, runtime: @runtime).observe(pane("turn_ended"))
      assert_equal 0, reminders
    end

    test "a turn end on two reads gets one reminder, and the agent is sent back to work" do
      assert_equal :nudged, observe_twice(pane("turn_ended"))

      assert_equal 1, reminders
      assert_includes @runtime.execs, [ "tmux", "send-keys", "-t", "agent", "Enter" ]
      assert_equal 1, @session.reload.metadata[TurnEndNudge::COUNT_KEY]
      assert_equal "ready", @session.state
    end

    test "a turn ended by a provider error gets the reminder too" do
      assert_equal :nudged, observe_twice(pane("turn_ended_provider_error"))
    end

    test "a screen that changed between the two reads starts over" do
      TurnEndNudge.new(@session, runtime: @runtime).observe(pane("turn_ended"))
      travel 1.minute

      assert_equal :pending, TurnEndNudge.new(@session.reload, runtime: @runtime).observe(pane("turn_ended_after_nudge"))
      assert_equal 0, reminders
    end

    test "a working agent is left alone and its remembered turn end forgotten" do
      TurnEndNudge.new(@session, runtime: @runtime).observe(pane("turn_ended"))

      assert_nil TurnEndNudge.new(@session.reload, runtime: @runtime).observe(pane("working"))
      refute @session.reload.metadata.key?(TurnEndNudge::SCREEN_KEY)
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

      assert_equal :nudged, TurnEndNudge.new(@session.reload, runtime: @runtime).observe(pane("turn_ended"))
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

    test "the turn end after the last reminder fails the session with a clear message" do
      @session.merge_jsonb!(:metadata, TurnEndNudge::COUNT_KEY => TurnEndNudge::LIMIT)

      assert_equal :failed, observe_twice(pane("turn_ended"))

      assert_equal 0, reminders
      @session.reload
      assert_equal "failed", @session.state
      assert_match(/ended its turn without calling `finish_session` 4 times/, @session.error_message)
      assert_match(/3 reminders/, @session.error_message)
    end

    test "every reminder counts toward the limit" do
      TurnEndNudge::LIMIT.times do |i|
        assert_equal :nudged, observe_twice(pane(i.even? ? "turn_ended" : "turn_ended_after_nudge"))
        travel 1.minute
      end

      assert_equal TurnEndNudge::LIMIT, reminders
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
