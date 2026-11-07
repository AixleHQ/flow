# frozen_string_literal: true

require "test_helper"

# ContainerRuntime::RunnerRuntime (DESIGN.md §5.3, §15 row 8): one runtime call
# is one op on the session's machine's queue, a session op names its session in
# the envelope, and an op that fails answers as the hosted runtime answers.
# FakeHostRunner (test/support/fakes/fake_host_runner.rb) answers the ops.
class ContainerRuntime::RunnerRuntimeTest < ActiveSupport::TestCase
  IMAGE = "ghcr.io/aixlehq/flow-claude-code:latest"

  setup do
    @runner = create(:runner, :manual, config: { "container" => { "network" => "host", "workspace_volume" => false,
                                                                  "resources" => { "cpus" => 2, "memory" => "8Gi" },
                                                                  "cache_mounts" => [ { "name" => "pip", "target" => "/home/agent/.cache/pip" } ] } })
    @environment = create(:runner_environment, runner: @runner, key: "aixle-r9-0a1b2c3d")
    @session = create(:runner_session, environment: @environment, runner_environment: nil)
    @host_runner = ContainerRuntime::FakeHostRunner.new(@environment)
    @runtime = ContainerRuntime::RunnerRuntime.new(@session)
  end

  teardown { @host_runner.stop }

  test "pull_image takes a free machine and ensures the image as it was given, as an environment op" do
    result = @runtime.pull_image(IMAGE)

    assert_equal({ status: :pulled, image: IMAGE, duration_seconds: 0 }, result)
    assert_equal @environment.id, @session.reload.runner_environment_id
    assert_equal @session.id, @environment.reload.current_session_id
    assert_equal [ { op: "image.ensure", session_id: nil, payload: { "image" => IMAGE } } ], @host_runner.operations
    assert @runtime.identity_before_pull?
    assert_equal "runner-session-#{@session.id}", @runtime.session_identity(@session)
  end

  test "the runner's image override is the image pulled and started" do
    @runner.update!(config: @runner.config.deep_merge("container" => { "image_override" => "registry.internal/agents/claude:7" }))

    @runtime.pull_image(IMAGE)
    @runtime.create_container(image: IMAGE, env_vars: [], host_config: {})

    assert_equal [ "registry.internal/agents/claude:7" ] * 2, @host_runner.operations.map { |op| op[:payload]["image"] }
  end

  test "create_container starts the container with the strategy's env and the runner's container options" do
    @runtime.pull_image(IMAGE)
    spec = { image: IMAGE, env_vars: [ "SESSION_ID=#{@session.id}", "TTYD_CMD=bash", "A=b=c" ],
             host_config: { "Memory" => 4.gigabytes, "CpuPeriod" => 100_000, "CpuQuota" => 200_000, "PidsLimit" => 4096 },
             privilege_escalation: false }

    handle = @runtime.create_container(spec)

    start = @host_runner.operations.last
    assert_equal "aixle-#{@environment.key}-#{@session.id}", handle
    assert_equal "container.start", start[:op]
    assert_equal @session.id, start[:session_id]
    assert_equal({
      "image" => IMAGE,
      "env" => { "SESSION_ID" => @session.id.to_s, "TTYD_CMD" => "bash", "A" => "b=c" },
      "workspace_volume" => false,
      "mounts" => [ { "type" => "cache", "name" => "pip", "target" => "/home/agent/.cache/pip" } ],
      "network" => "host", "pid" => "private",
      "resources" => { "cpus" => 2, "memory_bytes" => 8.gigabytes, "pids_limit" => 4096 },
      "privilege_escalation" => false
    }, start[:payload])
    assert_not start[:payload].key?("session_id"), "the session is in the envelope, not the payload"
    assert_equal handle, @runtime.start_container(handle)
    assert @runtime.wait_for_ready(handle)
  end

  test "every runtime call is one op, and each session op names the session" do
    start_session
    @host_runner.machine.on_exec { [ "out\n", "", 0 ] }
    @host_runner.operations.clear

    @runtime.exec("c", [ "true" ])
    @runtime.exec!("c", [ "true" ], timeout: 30)
    @runtime.write_file("c", "/tmp/x", "y", mode: 0o600, uid: 1000, gid: 1000)
    @runtime.read_file("c", "/tmp/x")
    @runtime.container_status("c")
    @runtime.container_logs("c")

    assert_equal %w[exec exec write_file read_file status logs], @host_runner.ops
    assert_equal [ @session.id ] * 6, @host_runner.operations.pluck(:session_id)
    assert_equal({ "cmd" => [ "true" ], "timeout" => 30 }, @host_runner.operations.second[:payload])
    assert_equal({ "path" => "/tmp/x", "content" => Base64.strict_encode64("y"), "mode" => 0o600, "uid" => 1000, "gid" => 1000 },
                 @host_runner.operations.third[:payload])
    assert_equal "y", @runtime.read_file("c", "/tmp/x")
    assert RunnerOperation.where(op: "exec").all? { |op| op.deadline_at <= 61.seconds.from_now }
    assert RunnerOperation.where.not(state: %w[pending delivered]).all? { |op| op.encrypted_payload.nil? }
  end

  test "an op that fails answers as the hosted runtime does" do
    start_session
    @host_runner.answer_with("exec", "status" => "expired")
    @host_runner.answer_with("read_file", "status" => "error", "error" => { "class" => "file_not_found", "message" => "no" })
    @host_runner.answer_with("status", "status" => "error", "error" => { "class" => "session_mismatch", "message" => "not yours" })

    assert_equal 1, @runtime.exec("c", [ "true" ]).last
    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!("c", [ "true" ]) }
    assert_nil @runtime.read_file("c", "/tmp/missing")
    assert_equal :missing, @runtime.container_status("c")
  end

  test "a session with no machine yet has no container" do
    assert_equal :missing, @runtime.container_status(nil)
    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!(nil, [ "true" ]) }
    assert @runtime.session_absent?(nil)
    assert_empty @host_runner.operations
  end

  test "cleanup stops the container, resets the machine and frees it" do
    start_session
    assert_not @runtime.session_absent?(nil), "a held machine still needs its reset"

    @runtime.cleanup_session(nil)

    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2)
    assert_equal [ @session.id, nil ], @host_runner.operations.last(2).pluck(:session_id)
    assert_nil @environment.reload.current_session_id
    assert @runtime.session_absent?(nil)
  end

  test "a failed reset moves the machine to failed, with the reason, and the session's cleanup is over" do
    start_session
    @host_runner.answer_with("env.reset", "status" => "error",
                                          "error" => { "class" => "reset_failed", "message" => "volume aixle-ws-x is in use" })

    @runtime.cleanup_session(nil)

    @environment.reload
    assert_equal "failed", @environment.state
    assert_nil @environment.current_session_id, "the session no longer holds it"
    assert_equal "env.reset failed after session #{@session.id}: reset_failed: volume aixle-ws-x is in use", @environment.state_reason
    assert @runtime.session_absent?(nil)
    assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(another_session) }
  end

  test "a failed container.stop is logged and the reset still runs" do
    start_session
    @host_runner.answer_with("container.stop", "status" => "error",
                                               "error" => { "class" => "docker_error", "message" => "the daemon refused" })

    @runtime.cleanup_session(nil)

    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2)
    assert_nil @environment.reload.current_session_id
    assert_equal "registered", @environment.state
  end

  test "a session that holds no machine sends nothing: its ops answer as a container that is not there" do
    start_session
    @runtime.cleanup_session(nil)
    @host_runner.operations.clear

    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!("c", [ "true" ]) }
    assert_equal 1, @runtime.exec("c", [ "true" ]).last
    assert_equal :missing, @runtime.container_status("c")
    assert_nil @runtime.read_file("c", "/tmp/x")
    assert_not @runtime.write_file("c", "/tmp/x", "y")
    assert_nothing_raised { @runtime.stop_container("c") }
    @runtime.cleanup_session(nil)

    assert_empty @host_runner.operations, "a late op of a finished session never reaches the machine"
  end

  test "an image.ensure that fails fails the pull with the runner's words" do
    @host_runner.answer_with("image.ensure", "status" => "error",
                                             "error" => { "class" => "image_pull_failed", "message" => "pull access denied" })

    error = assert_raises(ContainerRuntime::ImagePullError) { @runtime.pull_image("ghcr.io/aixlehq/nope:1") }

    assert_match(%r{Could not pull ghcr.io/aixlehq/nope:1: image.ensure failed: image_pull_failed: pull access denied}, error.message)
    assert_equal @session.id, @environment.reload.current_session_id, "the cleanup frees the machine (AdmittedPhaseActivity)"
  end

  test "a capped runtime, as the scanners use, gives every op that cap at most" do
    start_session
    capped = ContainerRuntime.for_session(@session, op_timeout: 15)

    capped.container_status(nil)

    assert_operator RunnerOperation.order(:id).last.deadline_at, :<=, 16.seconds.from_now
  end

  test "an op's deadline is the end of the activity that sends it, less the margin" do
    start_session
    finished = in_activity(20.0, DeadlineProbe)

    assert_operator finished, :<=, (21 - ContainerRuntime::RunnerRuntime::ACTIVITY_MARGIN).seconds.from_now
    assert_operator finished, :>=, (14 - ContainerRuntime::RunnerRuntime::ACTIVITY_MARGIN).seconds.from_now
  end

  # The wait for an op ends at its deadline, inside the activity, so an
  # unanswered reset reaches the machine's failure before the activity ends.
  test "cleanup inside an activity with an unanswered env.reset ends with the machine failed and the reason" do
    start_session
    @host_runner.answer_with("env.reset", :none)

    in_activity(ContainerRuntime::RunnerRuntime::ACTIVITY_MARGIN + 1.0, CleanupProbe)

    @environment.reload
    assert_equal "failed", @environment.state
    assert_nil @environment.current_session_id
    assert_equal "env.reset failed after session #{@session.id}: the runner did not answer", @environment.state_reason
    assert RunnerOperation.find_by(op: "env.reset").expired?
  end

  # Sends one op from inside an activity and reports its deadline.
  class DeadlineProbe < Temporalio::Activity::Definition
    def execute(runtime)
      runtime.container_status(nil)
      RunnerOperation.order(:id).last.deadline_at
    end
  end

  class CleanupProbe < Temporalio::Activity::Definition
    def execute(runtime)
      runtime.cleanup_session(nil)
      nil
    end
  end

  private

  def start_session
    @runtime.pull_image(IMAGE)
    @runtime.create_container(image: IMAGE, env_vars: [], host_config: {})
  end

  def another_session
    create(:runner_session, environment: @environment, runner_environment: nil)
  end

  def in_activity(timeout, activity)
    info = Temporalio::Testing::ActivityEnvironment.default_info.with(started_time: Time.current, start_to_close_timeout: timeout)
    Temporalio::Testing::ActivityEnvironment.new(info: info, activity_executors: TemporalActivityHelper::EXECUTORS)
                                            .run(activity, @runtime)
  end
end
