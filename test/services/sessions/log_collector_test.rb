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

    teardown do
      cleanup_runtime_overrides
      SessionLogUploader.storages.delete(PRESIGNED_KEY) if @registered_presigned_key
    end

    def collect(max_bytes: Sessions::LogCollector::DEFAULT_MAX_BYTES, cache_storage_key: :cache)
      LogCollector.new(
        session: @session,
        container: @container,
        adapter: @adapter,
        runtime: @runtime,
        redactor: SecretRedactor.for_session(@session),
        max_bytes: max_bytes,
        cache_storage_key: cache_storage_key
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

    # --- the container uploads its own logs ---
    #
    # The cap only ever existed because redaction ran in this process, which forced every
    # byte through it. Once the container scrubs its own logs the transfer is none of our
    # business, so these assert on who moves the bytes rather than on how many.

    # A cache storage that can sign a PUT, plus the other end of that PUT: the fake
    # container runtime records the transfer and this puts the bytes where the signed URL
    # said they would land, so the attachment that follows is a real one.
    PRESIGNED_KEY = :log_collector_test_cache

    # A cache storage that can sign a PUT, plus the other end of that PUT: the fake
    # container runtime records the transfer and this puts the bytes where the signed URL
    # said they would land, so the attachment that follows is a real one. Registered under
    # its own key rather than over :cache, because the signed URL and the attachment must
    # name the same storage and nothing else in the suite should see this one.
    def presigned_cache
      storage = Shrine::Storage::Memory.new
      def storage.presign(id, **) = { url: "https://storage.test/cache/#{id}" }

      # On the uploader's registry, which is the one the attachment resolves against — a
      # Shrine subclass copies the storages hash when it is defined, so registering on
      # Shrine alone is invisible here (and passes in isolation only because the subclass
      # had not been autoloaded yet).
      SessionLogUploader.storages[PRESIGNED_KEY] = storage
      @registered_presigned_key = true
      @runtime.on_upload { |_path, url, content| storage.upload(StringIO.new(content), url.split("/").last) }
      PRESIGNED_KEY
    end

    def with_filters
      @runtime.fs[LogCollector::FILTER_MARKER_PATH] = "# filters\n"
      yield
    end

    test "has the container PUT the log straight to storage when it scrubs its own logs" do
        with_filters { collect(max_bytes: 8, cache_storage_key: presigned_cache) }

      uploaded = @runtime.uploads.map { |u| u[:path] }
      assert_includes uploaded, "/home/claude/.claude/projects/-workspace/9d000c89.jsonl"
      assert_empty @runtime.execs.select { |c| c.join(" ").include?("tail -c") },
                   "a log the container uploaded was also read through this process"
    end

    test "keeps the whole log — an uploaded one is never truncated" do
      big = "x" * 5_000
      @runtime.fs["/var/log/mitm/http.log"] = big

      with_filters { collect(max_bytes: 8, cache_storage_key: presigned_cache) }

      log = @session.session_logs.find_by(name: "http.log")
      assert_equal big.bytesize, log.file_size
      assert_equal big, log.file.read
      assert_empty @session.session_logs.where(name: LogCollector::REPORT_NAME)
    end

    test "keeps the bounded read for a container built before the filters shipped" do
      collect(cache_storage_key: presigned_cache)

      assert_empty @runtime.uploads
      assert_not_nil @session.session_logs.find_by(name: "context.log")
    end

    test "hands an uploaded log back as a stream rather than a String" do
      @runtime.fs["/var/log/mitm/http.log"] = "{\"direction\":\"response\"}\n" * 3

      result = with_filters { collect(cache_storage_key: presigned_cache) }

      source = result.contents["logs/http.log"]
      assert_kind_of LogSource, source
      assert_equal 3, source.each_line.count
    end

    # A log an adapter parses for usage takes the same direct path as every other: the
    # transfer out of the container is what used to fail, not the parsing.
    test "uploads the log an adapter parses for usage like any other" do
      @adapter = Agents::CursorCliAdapter.new
      @runtime.fs["/var/log/mitm/http.log"] = "POST /v1/messages\n"

      with_filters { collect(cache_storage_key: presigned_cache) }

      assert_includes @runtime.uploads.map { |u| u[:path] }, "/var/log/mitm/http.log"
    end

    test "falls back to the bounded read when the upload fails, and says so" do
      @runtime.fail_exec("curl", stderr: "curl: (28) timeout", exit_code: 28)

      result = with_filters { collect(cache_storage_key: presigned_cache) }

      assert_includes result.failures.join, "fell back to a bounded read"
      assert_not_nil @session.session_logs.find_by(name: "context.log")
    end
  end
end
