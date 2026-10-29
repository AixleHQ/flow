# frozen_string_literal: true

require "test_helper"

module Sessions
  class LogTailTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, company: @user.companies.first, owner: @user)
      @session = create(:terminal_session, :failed, user: @user, project: @project, session_type: "workflow_step")
    end

    test "a read that stalls past the timeout returns a note instead of hanging" do
      Timeout.stubs(:timeout).raises(Timeout::Error)

      payload = LogTail.new(@session).call(lines: 40)

      assert_equal "unreachable", payload[:source]
      assert_equal "", payload[:log]
      assert_match(/timed out/, payload[:note])
    end

    test "a stored read whose tail lands mid-character still decodes as UTF-8" do
      content = "x#{'✻ ' * 200}\nfinal\n"
      create(:session_log, terminal_session: @session, name: "terminal_output.log",
                           file_size: content.bytesize,
                           file: SessionLogUploader.upload(StringIO.new(content), :store))

      payload = LogTail.new(@session).call(lines: 5)

      assert_equal "stored", payload[:source]
      assert_equal Encoding::UTF_8, payload[:log].encoding
      assert_match(/final/, payload[:log])
    end

    # Read the way the quota scan reads a pane (task #195): only the session's own
    # provider, only on the tail. Pattern text is split with `phrase` so this file
    # never matches a pattern itself.
    def phrase(*parts) = parts.join

    def stored_log(session, content)
      create(:session_log, terminal_session: session, name: "terminal_output.log",
                           file_size: content.bytesize,
                           file: SessionLogUploader.upload(StringIO.new(content), :store))
    end

    test "another provider's identifier in a session's own tool output is not reported as a quota error" do
      @session.update!(agent_type: "kiro_cli")
      stored_log(@session, phrase("app/frontend/pages/Projects/WorkflowRuns/ShowPage.tsx:442: {run.failureReason === 'quo",
                                  "ta_exc", "eeded' && (\n", "done\n"))

      payload = LogTail.new(@session).call(lines: 40)

      assert_equal "stored", payload[:source]
      assert_not payload.key?(:quota_error)
    end

    test "the session's own quota message at the end of its log is reported" do
      @session.update!(agent_type: "kiro_cli")
      stored_log(@session, phrase("working\n", "You have reached your mon", "thly usage lim", "it.\n"))

      payload = LogTail.new(@session).call(lines: 40)

      assert_equal :kiro, payload.dig(:quota_error, :provider)
    end

    test "a live pane is read with the session's own provider only" do
      runtime = stub_container_runtime
      session = create(:terminal_session, :running, user: @user, project: @project, session_type: "workflow_step",
                                                    agent_type: "kiro_cli")
      runtime.set_terminal_pane(phrase("{\"status\": \"RESOURCE_EXH", "AUSTED\"}\n", "● Thinking...\n"),
                                last_output_at: 5.minutes.ago)

      payload = LogTail.new(session).call(lines: 40)

      assert_equal "live", payload[:source]
      assert_not payload.key?(:quota_error)
    ensure
      cleanup_runtime_overrides
    end
  end
end
