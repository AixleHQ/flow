# frozen_string_literal: true

require "test_helper"

module Sessions
  class LogCollectorTest < ActiveSupport::TestCase
    setup do
      @runtime = stub_container_runtime
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
      @adapter = Agents::ClaudeCodeAdapter.new
      @container = @runtime.resolve_container(@session.container_id.presence || "abc123")
      @runtime.fs["/var/log/context.log"] = "injected context\n"
      @runtime.fs["/var/log/mitm/http.log"] = "POST /v1/messages\n"
      @runtime.fs["/home/claude/.claude/projects/-workspace/9d000c89.jsonl"] = %({"type":"assistant"}\n)
    end

    teardown { cleanup_runtime_overrides }

    def collect(max_bytes: Sessions::LogCollector::DEFAULT_MAX_BYTES)
      LogCollector.new(
        session: @session,
        container: @container,
        adapter: @adapter,
        runtime: @runtime,
        redactor: SecretRedactor.for_session(@session),
        max_bytes: max_bytes
      ).call
    end

    test "collects the agent's own transcript through the declared glob" do
      result = collect

      assert_empty result.failures
      log = @session.session_logs.find_by(name: "9d000c89.jsonl")
      assert_not_nil log, "the transcript matched by the glob was not collected"
      assert_equal %({"type":"assistant"}\n), log.file.read
      assert_equal %({"type":"assistant"}\n), result.contents["logs/9d000c89.jsonl"]
    end

    test "reads a bounded tail instead of copying the whole file" do
      @runtime.fs["/var/log/mitm/http.log"] = "old bytes" + ("x" * 100) + "the tail"

      collect(max_bytes: 8)

      command = @runtime.execs.find { |c| c.join(" ").include?("tail -c") }.join(" ")
      assert_match(/tail -c 8 /, command)
      assert_equal "the tail", @session.session_logs.find_by(name: "http.log").file.read
    end

    test "says in a report when a log was too large to collect whole" do
      @runtime.fs["/var/log/mitm/http.log"] = "y" * 50

      result = collect(max_bytes: 8)

      assert_includes result.failures.join, "/var/log/mitm/http.log — truncated: kept the last 8 of 50 bytes"
      report = @session.session_logs.find_by(name: LogCollector::REPORT_NAME)
      assert_not_nil report, "a truncated log left no trace of having been truncated"
      assert_includes report.file.read, "truncated"
    end

    test "reports a declared path the container does not have" do
      @runtime.fs.delete("/var/log/context.log")

      result = collect

      assert_includes result.failures.join, "/var/log/context.log — declared, but no such file"
    end

    test "stays silent about a glob that matches nothing" do
      @runtime.fs.delete("/home/claude/.claude/projects/-workspace/9d000c89.jsonl")

      result = collect

      assert_empty result.failures
      assert_nil @session.session_logs.find_by(name: LogCollector::REPORT_NAME)
    end

    test "reports a read failure rather than dropping the log silently" do
      @runtime.fail_read("/var/log/context.log")

      result = collect

      assert_includes result.failures.join, "/var/log/context.log — read failed"
      assert_nil @session.session_logs.find_by(name: "context.log")
      assert_not_nil @session.session_logs.find_by(name: LogCollector::REPORT_NAME)
    end

    test "redacts a session secret before the bytes are persisted" do
      item = create(:config_item, :secret, scope: @project, name: "API_TOKEN", value: "s3cr3t-value")
      @session.config_items << item
      @runtime.fs["/var/log/context.log"] = "called with s3cr3t-value\n"

      collect

      stored = @session.session_logs.find_by(name: "context.log").file.read
      assert_not_includes stored, "s3cr3t-value"
    end

    test "an empty log is neither persisted nor reported" do
      @runtime.fs["/var/log/context.log"] = ""

      result = collect

      assert_empty result.failures
      assert_nil @session.session_logs.find_by(name: "context.log")
    end
  end
end
