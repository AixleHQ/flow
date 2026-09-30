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
  end
end
