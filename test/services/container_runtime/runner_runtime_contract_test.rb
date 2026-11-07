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
  setup do
    @environment = create(:runner_environment, key: "aixle-r1-0a1b2c3d")
    @session = create(:runner_session, environment: @environment)
    @environment.update!(current_session: @session)
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
    gone = on_both { |runtime, _| Sessions::LiveLogReader.new(@session, runtime: runtime).tail(lines: 5).status }

    assert_same_on_both live
    assert_equal :ok, live["RunnerRuntime"][:status]
    assert_includes live["RunnerRuntime"][:text], "working..."
    assert_same_on_both gone
    assert_equal :unreachable, gone["RunnerRuntime"]
  end

  private

  def start_container
    @machine.start(@session.id)
  end

  # Runs the block on DockerRuntime, then on RunnerRuntime, with the session's
  # container as each one names it.
  def on_both(name = nil)
    name ||= @machine.container.name
    {
      "DockerRuntime" => yield(ContainerRuntime::DockerRuntime.new, name),
      "RunnerRuntime" => yield(ContainerRuntime::RunnerRuntime.new(@session), name)
    }
  end

  def assert_same_on_both(results)
    assert_equal results["DockerRuntime"], results["RunnerRuntime"], "DockerRuntime and RunnerRuntime answered differently"
  end
end
