# frozen_string_literal: true

require "test_helper"

module Sessions
  class LiveLogReaderTest < ActiveSupport::TestCase
    setup do
      @runtime = stub_container_runtime
      @user = create(:user, :with_company)
      @session = create(:terminal_session, :agent_session, :running, user: @user)
    end

    teardown { cleanup_runtime_overrides }

    test "returns the captured pane and the log's last write" do
      written_at = 4.minutes.ago
      @runtime.set_terminal_pane("building the thing\n", last_output_at: written_at)

      result = LiveLogReader.new(@session).tail(lines: 50)

      assert result.ok?
      assert_equal "building the thing\n", result.text
      assert_in_delta written_at.to_i, result.last_output_at.to_i, 1
    end

    test "asks for the requested number of lines in a single exec" do
      @runtime.set_terminal_pane("x\n")

      LiveLogReader.new(@session).tail(lines: 120)

      command = @runtime.execs.last.join(" ")
      assert_match(/capture-pane -t agent -p -S -120/, command)
      assert_match(/stat -c %Y #{Regexp.escape(LiveLogReader::TERMINAL_LOG_PATH)}/, command)
    end

    test "reports :not_ready when the container is up but tmux is not" do
      @runtime.fail_exec("capture-pane", stderr: "no server running on /dev/shm/tmux/default", exit_code: 1)

      result = LiveLogReader.new(@session).tail(lines: 50)

      assert_equal :not_ready, result.status
      assert_equal "", result.text
    end

    test "reports :unreachable when the container is gone" do
      @runtime.unreachable_on_exec("capture-pane")

      result = LiveLogReader.new(@session).tail(lines: 50)

      assert_equal :unreachable, result.status
      assert_nil result.last_output_at
    end

    test "reports :unreachable when the runtime cannot resolve the container at all" do
      @session.update!(container_id: nil)

      result = LiveLogReader.new(@session).tail(lines: 50)

      assert_equal :unreachable, result.status
    end
  end
end
