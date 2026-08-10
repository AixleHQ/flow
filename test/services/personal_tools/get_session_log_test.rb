# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class GetSessionLogTest < ActiveSupport::TestCase
    setup do
      @runtime = stub_container_runtime
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
    end

    teardown { cleanup_runtime_overrides }

    def execute(session, **params)
      GetSessionLog.new(params: { session_id: session.id, **params }, user: @user).execute
    end

    def payload(result) = JSON.parse(result[:stdout])

    def running_session
      create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    end

    def finished_session_with_log(content)
      session = create(:terminal_session, :agent_session, :collected, user: @user, project: @project)
      create(:session_log, terminal_session: session, name: "terminal_output.log",
             file: SessionLogUploader.upload(StringIO.new(content), :store),
             file_size: content.bytesize, content_type: "text/plain")
      session
    end

    test "reads a running session live and reports how long it has been silent" do
      @runtime.set_terminal_pane("compiling…\nstill compiling\n", last_output_at: 90.seconds.ago)

      body = payload(execute(running_session))

      assert_equal "live", body["source"]
      assert_match(/still compiling/, body["log"])
      assert_in_delta 90, body["idle_seconds"], 5
    end

    test "a container whose tmux is not up yet answers with a note, not an error" do
      @runtime.fail_exec("capture-pane", stderr: "no server running", exit_code: 1)

      result = execute(running_session)
      body = payload(result)

      assert_equal 0, result[:exit_code]
      assert_equal "live", body["source"]
      assert_equal "", body["log"]
      assert_match(/still starting/, body["note"])
    end

    test "a vanished container is reported as a finding, not a tool failure" do
      @runtime.unreachable_on_exec("capture-pane")

      result = execute(running_session)
      body = payload(result)

      assert_equal 0, result[:exit_code]
      assert_equal "unreachable", body["source"]
      assert_match(/watchdog/, body["note"])
    end

    test "a quota error in the tail is surfaced as a verdict" do
      @runtime.set_terminal_pane("API Error: Your credit balance is too low to run this request\n")

      body = payload(execute(running_session))

      assert_equal "anthropic", body.dig("quota_error", "provider")
      assert_match(/credit balance/i, body.dig("quota_error", "message"))
    end

    test "a finished session falls back to the stored log, ANSI stripped" do
      session = finished_session_with_log("\e[38;5;174mdone\e[0m\n")

      body = payload(execute(session))

      assert_equal "stored", body["source"]
      assert_equal "done\n", body["log"]
    end

    test "raw: true returns the stored bytes verbatim" do
      session = finished_session_with_log("\e[1mdone\e[0m\n")

      body = payload(execute(session, raw: true))

      assert_includes body["log"], "\e[1m"
    end

    test "the tail is limited to the requested number of lines" do
      session = finished_session_with_log((1..50).map { |i| "line #{i}\n" }.join)

      body = payload(execute(session, lines: 3))

      assert_equal [ "line 48", "line 49", "line 50" ], body["log"].lines.map(&:chomp)
    end

    test "a finished session with no captured log says so" do
      session = create(:terminal_session, :agent_session, :collected, user: @user, project: @project)

      body = payload(execute(session))

      assert_equal "none", body["source"]
      assert_equal "", body["log"]
    end

    test "a session in another company is not found" do
      stranger = create(:user, :with_company)
      theirs = create(:terminal_session, :agent_session, :running, user: stranger,
                      project: create(:project, owner: stranger, company: stranger.companies.first))

      assert_raises(PersonalTools::Base::NotFoundError) { execute(theirs) }
    end

    test "another member's unshared running session is not found" do
      other = create(:user)
      create(:company_membership, user: other, company: @company, role: :employee)
      theirs = create(:terminal_session, :agent_session, :running, user: other, project: @project)

      assert_raises(PersonalTools::Base::NotFoundError) { execute(theirs) }
    end
  end
end
