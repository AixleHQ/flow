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
    reader.expects(:tail).with(lines: 1).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    assert watchdog.stale?
  end

  test "stale? returns false when last output is within the threshold" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "recent output", last_output_at: 5.minutes.ago
    )
    reader = mock
    reader.expects(:tail).with(lines: 1).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    refute watchdog.stale?
  end

  test "stale? returns false when last_output_at is nil (container not ready for mtime yet)" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :ok, text: "", last_output_at: nil
    )
    reader = mock
    reader.expects(:tail).with(lines: 1).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    refute watchdog.stale?
  end

  test "stale? returns false when container is unreachable (leave to dead-container scanner)" do
    reader_result = Sessions::LiveLogReader::Result.new(
      status: :unreachable, text: "", last_output_at: nil
    )
    reader = mock
    reader.expects(:tail).with(lines: 1).returns(reader_result)
    Sessions::LiveLogReader.stubs(:new).with(@session, runtime: nil).returns(reader)

    watchdog = Sessions::NoOutputWatchdog.new(@session)
    refute watchdog.stale?
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
end
