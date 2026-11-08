# frozen_string_literal: true

require "test_helper"

class NoOutputWatchdogTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
    @session = create(:terminal_session, :running, user: @user, project: @project,
                      container_id: "ctr-abc",
                      started_at: 2.hours.ago,
                      session_type: "workflow_step",
                      state: "ready")
  end

  test "stale? returns true when last output is older than the threshold" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "some output", last_output_at: 45.minutes.ago
    )
    reader = mock
    reader.expects(:tail).with(lines: Sessions::NoOutputWatchdog::TAIL_LINES).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    assert watchdog.stale?
  end

  test "stale? returns false when last output is within the threshold" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "recent output", last_output_at: 5.minutes.ago
    )
    reader = mock
    reader.expects(:tail).with(lines: Sessions::NoOutputWatchdog::TAIL_LINES).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    refute_predicate watchdog, :stale?
  end

  test "stale? returns false when last_output_at is nil (container not ready for mtime yet)" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "", last_output_at: nil
    )
    reader = mock
    reader.expects(:tail).with(lines: Sessions::NoOutputWatchdog::TAIL_LINES).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    refute_predicate watchdog, :stale?
  end

  test "stale? returns false when container is unreachable (leave to dead-container scanner)" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :unreachable, text: "", last_output_at: nil
    )
    reader = mock
    reader.expects(:tail).with(lines: Sessions::NoOutputWatchdog::TAIL_LINES).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    refute_predicate watchdog, :stale?
  end

  test "message names an expired login when the pane still shows its banner" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "> /login\nLogin expired · Please run /login\n", last_output_at: 40.minutes.ago
    )
    reader = mock
    reader.stubs(:tail).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    assert_match(/authentication failed/i, watchdog.message)
    assert_match(/Login expired/, watchdog.message)
  end

  test "stale? and message share one read of the pane" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "still working", last_output_at: 40.minutes.ago
    )
    reader = mock
    reader.expects(:tail).once.returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    assert watchdog.stale?
    assert_match(/no output/i, watchdog.message)
  end

  test "message returns a human-readable no-output description" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "last line", last_output_at: 40.minutes.ago
    )
    reader = mock
    reader.stubs(:tail).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    assert_match(/no output/i, watchdog.message)
    assert_match(/30 minutes/i, watchdog.message)
  end

  def read_pane(text, last_output_at:)
    reader = stub(tail: Sessions::LiveLogReader::Result.new(status: :ok, text: text, last_output_at: last_output_at))
    Sessions::LiveLogReader.stubs(:new).returns(reader)
    Sessions::NoOutputWatchdog.new(@session.reload)
  end

  def kiro_pane(name) = file_fixture("terminal_panes/kiro_cli/#{name}.txt").read

  # Task #208, case 1: an idle Kiro repaints its unchanged screen, so the log keeps
  # getting bytes while nothing happens.
  test "a Kiro screen unchanged for 30 minutes is silent even while bytes keep arriving" do
    @session.update!(agent_type: "kiro_cli")
    refute_predicate read_pane(kiro_pane("turn_ended"), last_output_at: Time.current), :stale?
    travel 20.minutes
    refute_predicate read_pane(kiro_pane("turn_ended"), last_output_at: 5.seconds.ago), :stale?
    travel 11.minutes

    assert_predicate read_pane(kiro_pane("turn_ended"), last_output_at: 2.seconds.ago), :stale?
  end

  test "a working Kiro session's changing screen keeps it alive" do
    @session.update!(agent_type: "kiro_cli")
    working = kiro_pane("working")
    read_pane(working, last_output_at: Time.current).stale?
    travel 31.minutes

    refute_predicate read_pane(working.sub("Kiro is working · 6s", "Kiro is working · 31m 6s"),
                               last_output_at: 1.second.ago), :stale?
  end

  test "a first read judges by the last byte, as before" do
    @session.update!(agent_type: "kiro_cli")
    assert_predicate read_pane("some output", last_output_at: 45.minutes.ago), :stale?
  end

  # Sessions read by the token-refresh sweep: a parked session's repaints no longer pass
  # for an agent mid-turn, and a ticking working indicator still does.
  test "a shorter silence asked by the token-refresh sweep follows the screen too" do
    @session.update!(agent_type: "kiro_cli")
    read_pane(kiro_pane("turn_ended"), last_output_at: Time.current).stale?
    travel 11.minutes

    assert read_pane(kiro_pane("turn_ended"), last_output_at: 1.second.ago).silent_for?(10.minutes)
    refute read_pane(kiro_pane("working"), last_output_at: 1.second.ago).silent_for?(10.minutes)
  end

  # The screen rule is opt-in per runtime (SCREEN_RULE_RUNTIMES). A runtime whose working
  # screen has not been measured keeps the log-mtime rule, for the watchdog and for the
  # token-refresh sweep alike: an indicator that animates only through colour captures the
  # same on two reads while its agent works.
  test "a runtime outside the screen rule is judged by the log's last byte" do
    pane = "\u273B Thinking\u2026\n> \n"
    refute_predicate read_pane(pane, last_output_at: Time.current), :stale?
    travel 31.minutes

    watchdog = read_pane(pane, last_output_at: 2.seconds.ago)
    refute_predicate watchdog, :stale?
    refute watchdog.silent_for?(10.minutes)
    refute @session.reload.metadata.key?(Sessions::NoOutputWatchdog::SCREEN_KEY), "no screen record is kept"
  end

  test "a runtime outside the screen rule goes stale once its log stops getting bytes" do
    assert_predicate read_pane("\u273B Thinking\u2026\n> \n", last_output_at: 31.minutes.ago), :stale?
  end

  test "only Kiro is judged by its screen for now" do
    assert Sessions::NoOutputWatchdog.screen_rule?("kiro_cli")
    %w[claude_code codex cursor_cli gemini_cli antigravity_cli grok].each do |agent_type|
      refute Sessions::NoOutputWatchdog.screen_rule?(agent_type), agent_type
    end
  end

  test "message says the agent stopped without finish_session when the pane shows its idle prompt" do
    @session.update!(agent_type: "kiro_cli")
    watchdog = read_pane(kiro_pane("turn_ended_provider_error"), last_output_at: 40.minutes.ago)

    assert_predicate watchdog, :stale?
    assert_match(/ended its turn without calling `finish_session`/, watchdog.message)
    assert_match(/30 minutes/, watchdog.message)
  end
end
