# frozen_string_literal: true

require "test_helper"

# DESIGN.md §15 row 8, requirement 2: the runner behaves as hosted does for the
# same strategy code. Each scenario runs once on DockerRuntime and once on
# RunnerRuntime, against the same machine (ContainerRuntime::FakeMachine), and
# the strategy must get the same result from both.
#
# What answers each side: DockerRuntime talks to the Docker Engine API, which
# FakeDockerEngine serves over WebMock from the machine; RunnerRuntime puts its
# ops on the machine's real queue (Runners::Operations), and FakeHostRunner
# answers them from the same machine with the results PROTOCOL.md §6
# specifies. That is where the two models differ, and where the strategy code
# could see a difference. The Go runner's own handling of each op is tested
# against the protocol in runner/internal/docker, and the wire by the
# conformance fixtures.
class ContainerRuntime::RunnerRuntimeContractTest < ActiveSupport::TestCase
  MITM_LOG = "/var/log/mitm/http.log"

  setup do
    @environment = create(:runner_environment, key: "aixle-r1-0a1b2c3d")
    @session = create(:runner_session, environment: @environment)
    @environment.update!(current_session: @session)
    # RunnerRuntime finds the session from the admission whose runtime_id
    # names the container, as AdmittedPhaseActivity writes it after the create.
    ContainerRuntime::FakeHostRunner.identify!(@session, "aixle-#{@environment.key}-#{@session.id}")
    @machine = ContainerRuntime::FakeMachine.new(key: @environment.key)
    @host_runner = ContainerRuntime::FakeHostRunner.new(@environment, machine: @machine)
    @engine = ContainerRuntime::FakeDockerEngine.new(@machine).install!
  end

  teardown do
    @host_runner.stop
    @engine.uninstall!
  end

  test "a step that succeeds" do
    start_container
    @machine.container.files["/workspace/outputs/report.md"] = "# Done\n"
    @machine.on_exec { |cmd| [ cmd.last == "find /workspace/outputs -type f" ? "/workspace/outputs/report.md\n" : "", "", 0 ] }

    results = on_both do |runtime, container|
      stdout, stderr, code = runtime.exec(container, [ "/bin/sh", "-c", "find /workspace/outputs -type f" ],
                                          stdout: true, stderr: true)
      [ stdout.join, stderr.join, code, runtime.write_file(container, "/tmp/.aixle-prompt", "go", mode: 0o600, uid: 1000, gid: 1000),
        runtime.read_file(container, "/workspace/outputs/report.md"), runtime.container_status(container) ]
    end

    assert_same_on_both results
    assert_equal [ "/workspace/outputs/report.md\n", "", 0, true, "# Done\n", :running ], results["RunnerRuntime"]
  end

  test "an exec with a non-zero code" do
    start_container
    @machine.on_exec { [ "partial\n", "boom\n", 3 ] }

    results = on_both do |runtime, container|
      stdout, stderr, code = runtime.exec(container, [ "sh", "-c", "make test" ])
      [ stdout.join, stderr.join, code ]
    end

    assert_same_on_both results
    assert_equal [ "partial\n", "boom\n", 3 ], results["RunnerRuntime"]
  end

  test "a failed write" do
    start_container
    @machine.fail_writes = true

    results = on_both { |runtime, container| runtime.write_file(container, "/tmp/.aixle-prompt", "go", mode: 0o600) }

    assert_same_on_both results
    assert_equal false, results["RunnerRuntime"] # rubocop:disable Minitest/RefuteFalse
  end

  test "exec! with no container" do
    results = on_both("aixle-#{@environment.key}-#{@session.id}") do |runtime, container|
      runtime.exec!(container, [ "tmux", "capture-pane", "-t", "agent", "-p" ])
    rescue ContainerRuntime::ContainerUnreachableError => e
      e.class
    end

    assert_same_on_both results
    assert_equal ContainerRuntime::ContainerUnreachableError, results["RunnerRuntime"]
  end

  test "the live log reads the same through both, and an unreachable container the same" do
    start_container
    @session.update!(container_id: @machine.container.name)
    @machine.on_exec { [ "1793455200\n__aixle_pane__\n$ claude\nworking...\n", "", 0 ] }

    live = on_both { |runtime, _| Sessions::LiveLogReader.new(@session, runtime: runtime).tail(lines: 5).to_h }
    @machine.reset
    gone = on_both(@session.container_id) { |runtime, _| Sessions::LiveLogReader.new(@session, runtime: runtime).tail(lines: 5).status }

    assert_same_on_both live
    assert_equal :ok, live["RunnerRuntime"][:status]
    assert_includes live["RunnerRuntime"][:text], "working..."
    assert_same_on_both gone
    assert_equal :unreachable, gone["RunnerRuntime"]
  end

  # The usage of `cursor_cli`, `grok` and the Codex fallback is read from the
  # session's MITM log. The strategy gets that log through the runtime
  # (Sessions::LogCollector: an exec for the listing and the tail), so a runner
  # session records usage when the same adapters price what RunnerRuntime returns.
  test "the MITM log of a runner session is read through the runtime and grok prices it" do
    start_container
    @session.update!(agent_type: "grok")
    log = "#{grok_mitm_line}\n"
    @machine.container.files[MITM_LOG] = log
    stub_request(:get, GrokAdapter::MODELS_URL).to_return(status: 401, body: "")

    runtime = ContainerRuntime::RunnerRuntime.new
    assert_equal log, runtime.read_file(@machine.container.name, MITM_LOG)
    artifacts = collect_logs(runtime, Agents::GrokAdapter.new)
    Agents::GrokAdapter.new.collect_usage(@session, artifacts)

    stat = @session.reload.usage_statistic
    assert_equal 1_000, stat.input_tokens
    assert_equal 200, stat.output_tokens
    assert_equal "mitm", stat.source
  end

  test "the MITM log of a runner session is read through the runtime and cursor_cli prices it" do
    start_container
    @session.update!(agent_type: "cursor_cli")
    create(:agent_credential, :cursor_cli, user: @session.user, config_data: { "accessToken" => "session-token" })
    response_iso = "2026-05-21T19:32:31.000Z"
    log = [
      { ts: "2026-05-21T19:32:30.461Z", direction: "request", path: "/agent.v1.AgentService/Run",
        headers: { "x-request-id" => "req-1" }, _source: "http2-logger" },
      { ts: response_iso, direction: "response", path: "/agent.v1.AgentService/Run",
        headers: { "x-request-id" => "req-1" }, _source: "http2-logger" }
    ].map(&:to_json).join("\n")
    @machine.container.files[MITM_LOG] = log
    response_ms = Time.iso8601(response_iso).to_i * 1000
    stub_request(:post, "https://api2.cursor.sh/aiserver.v1.DashboardService/GetFilteredUsageEvents")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "usageEventsDisplay" => [ {
                   "timestamp" => (response_ms + 100).to_s, "model" => "claude-4-sonnet",
                   "tokenUsage" => { "inputTokens" => 1000, "outputTokens" => 200, "totalCents" => 3.5 }
                 } ] }.to_json)

    runtime = ContainerRuntime::RunnerRuntime.new
    artifacts = collect_logs(runtime, Agents::CursorCliAdapter.new)
    assert_equal log, artifacts["logs/http.log"]
    Agents::CursorCliAdapter.new.collect_usage(@session, artifacts)

    stat = @session.reload.usage_statistic
    assert_equal 1_000, stat.input_tokens
    assert_equal 200, stat.output_tokens
    assert_equal "cursor_api", stat.source
  end

  private

  def grok_mitm_line
    body = { model: "grok-4.5", usage: { prompt_tokens: 1_000, completion_tokens: 200, total_tokens: 1_200,
                                         prompt_tokens_details: { cached_tokens: 400 },
                                         completion_tokens_details: { reasoning_tokens: 50 } } }.to_json
    { _source: "http2-logger", direction: "response", host: "api.x.ai", path: "/v1/chat/completions",
      status_code: 200, ts: "2026-08-14T12:00:00.000000Z", body: body }.to_json
  end

  # What the strategy does at cleanup: collect the adapter's declared logs
  # through the runtime. The machine answers the listing and the tail from the
  # container's files.
  def collect_logs(runtime, adapter)
    @machine.on_exec do |cmd|
      script = cmd.last
      path = @machine.container.files.keys.find { |file| script.include?(file) }
      if script.start_with?("for f in")
        [ "#{path}#{Sessions::LogCollector::FIELD_SEPARATOR}#{@machine.container.files[path].bytesize}\n", "", 0 ]
      else
        [ @machine.container.files[path].to_s, "", 0 ]
      end
    end
    Sessions::LogCollector.new(session: @session, container: @machine.container.name, adapter: adapter,
                               runtime: runtime, redactor: ->(content) { content }).call.contents
  end

  def start_container
    @machine.start(@session.id)
  end

  # Runs the block on DockerRuntime, then on RunnerRuntime, with the session's
  # container as each one names it.
  def on_both(name = nil)
    name ||= @machine.container.name
    {
      "DockerRuntime" => yield(ContainerRuntime::DockerRuntime.new, name),
      "RunnerRuntime" => yield(ContainerRuntime::RunnerRuntime.new, name)
    }
  end

  def assert_same_on_both(results)
    assert_equal results["DockerRuntime"], results["RunnerRuntime"], "DockerRuntime and RunnerRuntime answered differently"
  end
end
