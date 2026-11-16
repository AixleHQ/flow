# frozen_string_literal: true

require "test_helper"
require "open3"
require "socket"

module Agents
  # docker/base/logger/otlp_hook.py is the command of every lifecycle hook Flow installs
  # for the runtimes without OpenTelemetry of their own (docs/design/agent-telemetry.md §3).
  # It runs inside the agent's turn, so it is exercised as the python3 script it is.
  class OtlpHookTest < ActiveSupport::TestCase
    HOOK = Rails.root.join("docker/base/logger/otlp_hook.py").to_s
    SESSION = "terminal_session_token=rt-1,terminal_session_key=k-1"

    setup do
      @collector = TCPServer.new("127.0.0.1", 0)
      @requests = Queue.new
      @answer = Queue.new
      @thread = Thread.new { serve }
    end

    teardown do
      @answer << true
      @collector.close
      @thread.join(5)
    end

    test "the event reaches the collector unchanged, as one log record of the session, without holding the agent" do
      event = { "hook_event_name" => "PostToolUse", "tool_name" => "shell", "tool_response" => "done ✓" }.to_json
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      out, status = run_hook("kiro-cli", "PostToolUse", stdin: event)

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3, "the hook waited for the collector"
      assert_equal [ "", 0 ], [ out, status.exitstatus ]
      path, body = @requests.pop(timeout: 5)
      assert_equal "/v1/logs", path
      resource_log = JSON.parse(body).dig("resourceLogs", 0)
      assert_equal({ "service.name" => "kiro-cli", "terminal_session_token" => "rt-1", "terminal_session_key" => "k-1" },
                   attributes(resource_log.dig("resource", "attributes")))
      assert_equal "aixle_flow.hooks", resource_log.dig("scopeLogs", 0, "scope", "name")
      record = resource_log.dig("scopeLogs", 0, "logRecords", 0)
      assert_equal event, record.dig("body", "stringValue")
      assert_equal({ "event.name" => "PostToolUse" }, attributes(record["attributes"]))
    end

    test "the reply a CLI expects is the only thing printed" do
      out, status = run_hook("cursor-agent", "beforeSubmitPrompt", '{"continue":true}', stdin: "{}")

      assert_equal [ '{"continue":true}', 0 ], [ out, status.exitstatus ]
    end

    test "without a session, or with the collector down, the hook succeeds and sends nothing" do
      unproven, unproven_status = run_hook("kiro-cli", "Stop", stdin: "{}", session: nil)
      down, down_status = run_hook("kiro-cli", "Stop", stdin: "{}", endpoint: "http://127.0.0.1:9")

      assert_equal [ "", 0, "", 0 ], [ unproven, unproven_status.exitstatus, down, down_status.exitstatus ]
      assert_nil @requests.pop(timeout: 1)
    end

    private

    def run_hook(service, event, *reply, stdin:, session: SESSION, endpoint: "http://127.0.0.1:#{@collector.addr[1]}")
      env = { "AIXLE_OTLP_RESOURCE_ATTRIBUTES" => session, "AIXLE_OTLP_ENDPOINT" => endpoint }
      out, _err, status = Open3.capture3(env, "python3", "-I", HOOK, service, event, *reply, stdin_data: stdin)
      [ out, status ]
    end

    def serve
      loop do
        client = @collector.accept
        path = client.gets.split[1]
        length = 0
        while (line = client.gets) && line != "\r\n"
          length = line.split(":", 2).last.to_i if line.downcase.start_with?("content-length:")
        end
        @requests << [ path, client.read(length).force_encoding(Encoding::UTF_8) ]
        @answer.pop(timeout: 10)
        client.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
        client.close
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def attributes(list)
      Array(list).to_h { |kv| [ kv["key"], kv["value"].values.first ] }
    end
  end
end
