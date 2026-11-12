# frozen_string_literal: true

require "test_helper"

# ContainerRuntime::RunnerRuntime (DESIGN.md §5.3, §15 row 8): one runtime call
# is one op on the session's machine's queue, a session op names its session in
# the envelope, and an op that fails answers as the hosted runtime answers.
# One runtime serves any session: each call finds its session from its own
# argument. FakeHostRunner (test/support/fakes/fake_host_runner.rb) answers the
# ops.
class ContainerRuntime::RunnerRuntimeTest < ActiveSupport::TestCase
  IMAGE = "ghcr.io/aixlehq/flow-claude-code:latest"

  setup do
    @runner = create(:runner, :manual, config: { "container" => { "network" => "host", "workspace_volume" => false,
                                                                  "resources" => { "cpus" => 2, "memory" => "8Gi" },
                                                                  "cache_mounts" => [ { "name" => "pip", "target" => "/home/agent/.cache/pip" } ] } })
    @environment = create(:runner_environment, runner: @runner, key: "aixle-r9-0a1b2c3d")
    @session = create(:runner_session, environment: @environment, runner_environment: nil)
    @host_runner = ContainerRuntime::FakeHostRunner.new(@environment)
    @runtime = ContainerRuntime::RunnerRuntime.new
    @identity = @runtime.session_identity(@session)
    ContainerRuntime::FakeHostRunner.identify!(@session, @identity)
  end

  teardown { @host_runner.stop }

  test "pull_image does nothing, as on Kubernetes: the runner pulls in container.start" do
    result = @runtime.pull_image(IMAGE)

    assert_equal({ status: :skipped, image: IMAGE, duration_seconds: 0 }, result)
    assert_empty @host_runner.operations
    assert_nil @environment.reload.current_session_id, "no machine is taken before the create"
    assert_equal "runner-session-#{@session.id}", @identity
  end

  test "without network: host, container.start sends the sidecar's port from Settings" do
    @runner.update!(config: @runner.config.deep_merge("container" => { "network" => "bridge" }))
    Settings.runners.stubs(:proxy).returns(Hashie::Mash.new(port: 7800, host_port_base: 20_000, host_port_span: 10_000))

    @runtime.create_container(spec)

    assert_equal 7800, @host_runner.operations.sole[:payload]["proxy_port"]
  end

  test "the runner's image override is the image started" do
    @runner.update!(config: @runner.config.deep_merge("container" => { "image_override" => "registry.internal/agents/claude:7" }))

    @runtime.create_container(spec)

    assert_equal [ "registry.internal/agents/claude:7" ], @host_runner.operations.map { |op| op[:payload]["image"] }
  end

  test "create_container takes a free machine and starts the container with the strategy's env and the runner's options" do
    spec = spec(env_vars: [ "SESSION_ID=#{@session.id}", "TTYD_CMD=bash", "A=b=c" ],
                host_config: { "Memory" => 4.gigabytes, "CpuPeriod" => 100_000, "CpuQuota" => 200_000, "PidsLimit" => 4096 })

    handle = @runtime.create_container(spec)

    assert_equal @environment.id, @session.reload.runner_environment_id
    assert_equal @session.id, @environment.reload.current_session_id
    start = @host_runner.operations.sole
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
      "privilege_escalation" => false,
      "proxy_port" => 20_000 + (@session.id % 10_000)
    }, start[:payload])
    assert_not start[:payload].key?("session_id"), "the session is in the envelope, not the payload"
    assert_equal [ IMAGE ], @host_runner.machine.images, "container.start pulled the image"
    ContainerRuntime::FakeHostRunner.identify!(@session, handle)
    assert_equal handle, @runtime.start_container(handle)
    assert @runtime.wait_for_ready(handle)
  end

  test "a create's spec without the session label is refused before anything is sent" do
    assert_raises(ArgumentError) { @runtime.create_container(image: IMAGE, env_vars: [], host_config: {}, labels: {}) }
    assert_empty @host_runner.operations
  end

  test "every runtime call is one op, and each session op names the session" do
    handle = start_session
    @host_runner.machine.on_exec { [ "out\n", "", 0 ] }
    @host_runner.operations.clear

    @runtime.exec(handle, [ "true" ])
    @runtime.exec!(handle, [ "true" ], timeout: 30)
    @runtime.write_file(handle, "/tmp/x", "y", mode: 0o600, uid: 1000, gid: 1000)
    @runtime.read_file(handle, "/tmp/x")
    @runtime.container_status(handle)
    @runtime.container_logs(handle)

    assert_equal %w[exec exec write_file read_file status logs], @host_runner.ops
    assert_equal [ @session.id ] * 6, @host_runner.operations.pluck(:session_id)
    assert_equal({ "cmd" => [ "true" ], "timeout" => 30 }, @host_runner.operations.second[:payload].except("uploads"))
    assert_equal({ "path" => "/tmp/x", "content" => Base64.strict_encode64("y"), "mode" => 0o600, "uid" => 1000, "gid" => 1000 },
                 @host_runner.operations.third[:payload])
    assert_equal "y", @runtime.read_file(handle, "/tmp/x")
    assert RunnerOperation.where(op: "exec").all? { |op| op.deadline_at <= 61.seconds.from_now }
    assert RunnerOperation.where.not(state: %w[pending delivered]).all? { |op| op.encrypted_payload.nil? }
  end

  test "one runtime serves any session: each call finds its session from the admission of its id" do
    other_environment = create(:runner_environment, runner: @runner, key: "aixle-r9-4e5f6a7b")
    other_runner = ContainerRuntime::FakeHostRunner.new(other_environment)
    first = start_session
    other = create(:runner_session, environment: other_environment, runner_environment: nil)
    second = @runtime.create_container(spec(session: other))
    ContainerRuntime::FakeHostRunner.identify!(other, second)

    assert_equal :running, @runtime.container_status(first)
    assert_equal :running, @runtime.container_status(second)
    assert_equal [ @session.id ] * 2, @host_runner.operations.pluck(:session_id)
    assert_equal [ other.id ] * 2, other_runner.operations.pluck(:session_id)
    assert_equal "aixle-#{other_environment.key}-#{other.id}", second
  ensure
    other_runner&.stop
  end

  test "an id that no runner admission has answers as a container that is not there, and sends nothing" do
    start_session
    @host_runner.operations.clear

    assert_equal :missing, @runtime.container_status("aixle-#{@environment.key}-999999")
    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!(nil, [ "true" ]) }
    assert @runtime.session_absent?("not-an-admission")
    assert_empty @host_runner.operations
  end

  test "an op that fails answers as the hosted runtime does" do
    handle = start_session
    @host_runner.answer_with("exec", "status" => "expired")
    @host_runner.answer_with("read_file", "status" => "error", "error" => { "class" => "file_not_found", "message" => "no" })
    @host_runner.answer_with("status", "status" => "error", "error" => { "class" => "session_mismatch", "message" => "not yours" })

    assert_equal 1, @runtime.exec(handle, [ "true" ]).last
    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!(handle, [ "true" ]) }
    assert_nil @runtime.read_file(handle, "/tmp/missing")
    assert_equal :missing, @runtime.container_status(handle)
  end

  test "a session with no machine yet has no container" do
    assert_equal :missing, @runtime.container_status(@identity)
    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!(@identity, [ "true" ]) }
    assert @runtime.session_absent?(@identity)
    assert_empty @host_runner.operations
  end

  test "cleanup stops the container, resets the machine and frees it" do
    handle = start_session
    assert_not @runtime.session_absent?(handle), "a held machine still needs its reset"

    @runtime.cleanup_session(handle)

    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2)
    assert_equal [ @session.id, nil ], @host_runner.operations.last(2).pluck(:session_id)
    assert_nil @environment.reload.current_session_id
    assert @runtime.session_absent?(handle)
  end

  test "the cleanup identity finds the session as its container's name does" do
    start_session(identify: false)

    assert_not @runtime.session_absent?(@identity)
    @runtime.cleanup_session(@identity)

    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2)
    assert_nil @environment.reload.current_session_id
  end

  test "a failed reset moves the machine to failed, with the reason, and the session's cleanup is over" do
    handle = start_session
    @host_runner.answer_with("env.reset", "status" => "error",
                                          "error" => { "class" => "reset_failed", "message" => "volume aixle-ws-x is in use" })

    @runtime.cleanup_session(handle)

    @environment.reload
    assert_equal "failed", @environment.state
    assert_nil @environment.current_session_id, "the session no longer holds it"
    assert_equal "env.reset failed after session #{@session.id}: reset_failed: volume aixle-ws-x is in use", @environment.state_reason
    assert @runtime.session_absent?(handle)
    assert_raises(Runners::Machines::NoMachine) { Runners::Machines.acquire!(another_session) }
  end

  test "a failed container.stop is logged and the reset still runs" do
    handle = start_session
    @host_runner.answer_with("container.stop", "status" => "error",
                                               "error" => { "class" => "docker_error", "message" => "the daemon refused" })

    @runtime.cleanup_session(handle)

    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2)
    assert_nil @environment.reload.current_session_id
    assert_equal "registered", @environment.state
  end

  test "a session that holds no machine sends nothing: its ops answer as a container that is not there" do
    handle = start_session
    @runtime.cleanup_session(handle)
    @host_runner.operations.clear

    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!(handle, [ "true" ]) }
    assert_equal 1, @runtime.exec(handle, [ "true" ]).last
    assert_equal :missing, @runtime.container_status(handle)
    assert_nil @runtime.read_file(handle, "/tmp/x")
    assert_not @runtime.write_file(handle, "/tmp/x", "y")
    assert_nothing_raised { @runtime.stop_container(handle) }
    @runtime.cleanup_session(handle)

    assert_empty @host_runner.operations, "a late op of a finished session never reaches the machine"
  end

  test "a pull that fails in container.start fails the create with the runner's words, and the machine waits for the cleanup" do
    @host_runner.answer_with("container.start", "status" => "error",
                                                "error" => { "class" => "image_pull_failed", "message" => "pull access denied" })

    error = assert_raises(ContainerRuntime::CreateRefusedError) { @runtime.create_container(spec(image: "ghcr.io/aixlehq/nope:1")) }

    assert_match(%r{Could not pull ghcr.io/aixlehq/nope:1: container.start failed: image_pull_failed: pull access denied}, error.message)
    assert_equal @session.id, @environment.reload.current_session_id, "the cleanup frees the machine (AdmittedPhaseActivity)"
    assert_not @runtime.session_absent?(@identity)
  end

  test "every refusal the runner answers is a refused create; an expired create is not" do
    %w[container_start_failed volume_not_owned forbidden_mount invalid_payload].each do |klass|
      @host_runner.answer_with("container.start", "status" => "error", "error" => { "class" => klass, "message" => "no" })

      error = assert_raises(ContainerRuntime::CreateRefusedError, klass) { @runtime.create_container(spec) }
      assert_match(/container.start failed: #{klass}: no/, error.message)
    end
    @host_runner.answer_with("container.start", "status" => "expired")

    error = assert_raises(RuntimeError) { @runtime.create_container(spec) }
    assert_not_kind_of ContainerRuntime::CreateRefusedError, error, "nobody knows what an expired create left"
  end

  # The holder was read before the pause; the machine changed hands during it.
  test "a session op and an env.reset of a session that released its machine after the read are not created" do
    handle = start_session
    observed = Runners::Machines.held_by(@session)
    Runners::Machines.release!(observed, @session)
    next_session = another_session
    Runners::Machines.acquire!(next_session)
    Runners::Machines.stubs(:held_by).with(@session).returns(observed)
    Runners::Machines.stubs(:held_by).with(next_session).returns(@environment.reload)
    @host_runner.operations.clear

    assert_raises(ContainerRuntime::ContainerUnreachableError) { @runtime.exec!(handle, [ "true" ]) }
    @runtime.cleanup_session(handle)

    assert_empty @host_runner.operations, "neither op reached the next session's machine"
    @environment.reload
    assert_equal [ "registered", next_session.id ], [ @environment.state, @environment.current_session_id ],
                 "the late reset's failure leaves the next session's hold alone"
  end

  test "the cleanup is not ready while an op of the session is unfinished on its machine" do
    handle = start_session
    assert @runtime.cleanup_ready?(handle)
    @host_runner.answer_with("logs", :none)
    operation = Runners::Operations.enqueue!(@environment, op: "logs", payload: {}, deadline_at: 1.minute.from_now,
                                                           session: @session)

    assert_not @runtime.cleanup_ready?(handle)
    Runners::Operations.record_result!(operation, status: "ok", data: { "tail" => "" })
    assert @runtime.cleanup_ready?(handle)
    assert @runtime.cleanup_ready?("not-an-admission"), "a session without a machine has nothing queued"
  end

  # The session holds the machine, so every op on it is the session's, an
  # env.reset, which names no session, included.
  test "a cleanup retry behind an unfinished env.reset queues nothing until that reset finishes or expires" do
    handle = start_session
    @host_runner.answer_with("env.reset", :none)
    pending_reset = Runners::Operations.enqueue!(@environment, op: "env.reset", payload: {}, deadline_at: 1.minute.from_now,
                                                               session: @session)
    assert_nil pending_reset.terminal_session_id
    @host_runner.operations.clear

    assert_not @runtime.cleanup_ready?(handle), "the retry would queue container.stop and env.reset behind the reset"
    Runners::Operations.expire!(pending_reset)
    assert @runtime.cleanup_ready?(handle), "an expired reset holds the cleanup up no longer"

    finished_reset = Runners::Operations.enqueue!(@environment, op: "env.reset", payload: {}, deadline_at: 1.minute.from_now,
                                                                session: @session)
    assert_not @runtime.cleanup_ready?(handle)
    Runners::Operations.record_result!(finished_reset, status: "ok", data: { "removed_containers" => [] })
    assert @runtime.cleanup_ready?(handle), "a finished reset holds the cleanup up no longer"
    assert_equal %w[env.reset], @host_runner.ops, "nothing but the test's own reset was queued"
  end

  # The admission's runtime_id is what create_container returns, and every
  # later call resolves its session from it: the runner's answer must not
  # choose it.
  test "a container.start answer that names another session's container is an error, and no later call reaches that session" do
    # Another runner, so that the other session cannot take this session's machine.
    other_environment = create(:runner_environment, runner: create(:runner, :manual), key: "aixle-r9-4e5f6a7b")
    other_runner = ContainerRuntime::FakeHostRunner.new(other_environment)
    other = create(:runner_session, environment: other_environment, runner_environment: nil)
    others_container = @runtime.create_container(spec(session: other))
    assert_equal other.id, other_environment.reload.current_session_id
    ContainerRuntime::FakeHostRunner.identify!(other, others_container)
    other_runner.operations.clear
    @host_runner.answer_with("container.start") do |_payload, session_id|
      @host_runner.machine.start(session_id)
      { "status" => "ok", "data" => { "container_id" => "f" * 64, "name" => others_container } }
    end

    error = assert_raises(RuntimeError) { @runtime.create_container(spec) }

    assert_not_kind_of ContainerRuntime::CreateRefusedError, error, "the runner may have created a container"
    assert_match(/answered the container "#{others_container}", not the session's "aixle-#{@environment.key}-#{@session.id}"/,
                 error.message)
    # The admission keeps the cleanup identity, as AdmittedPhaseActivity leaves it after a failed create.
    @runtime.container_status(@identity)
    @runtime.cleanup_session(@identity)
    assert_empty other_runner.operations, "no call of the session reached the other session's machine"
    assert_equal %w[container.start status container.stop env.reset], @host_runner.ops
    assert_equal other.id, other_environment.reload.current_session_id
    assert_equal :running, @runtime.container_status(others_container)
  ensure
    other_runner&.stop
  end

  test "a capped runtime, as the scanners use, gives every op that cap at most" do
    handle = start_session
    capped = ContainerRuntime.for_session(@session, op_timeout: 15)

    capped.container_status(handle)

    assert_operator RunnerOperation.order(:id).last.deadline_at, :<=, 16.seconds.from_now
  end

  test "an op's deadline is the end of the activity that sends it, less the margin" do
    handle = start_session
    finished = in_activity(20.0, DeadlineProbe, handle)

    assert_operator finished, :<=, (21 - ContainerRuntime::RunnerRuntime::ACTIVITY_MARGIN).seconds.from_now
    assert_operator finished, :>=, (14 - ContainerRuntime::RunnerRuntime::ACTIVITY_MARGIN).seconds.from_now
  end

  # == output and files over the 1 MiB output cap (PROTOCOL.md §6.5) ==

  test "an exec and a read_file carry a signed upload slot for each output, valid past the op's deadline" do
    handle = start_session
    @host_runner.operations.clear

    @runtime.exec(handle, [ "true" ], timeout: 30)
    @runtime.read_file(handle, "/tmp/x")
    @runtime.write_file(handle, "/tmp/x", "y")

    exec, read, write = @host_runner.operations.pluck(:payload)
    assert_equal %w[stdout stderr], exec["uploads"].keys
    assert_equal %w[content], read["uploads"].keys
    assert_not write.key?("uploads"), "only the ops that return output carry slots"
    slot = exec["uploads"]["stdout"]
    assert_equal %w[id max_bytes url], slot.keys.sort
    assert_equal Settings.runners.upload_limit, slot["max_bytes"]
    assert_match(/\A\h{60}\z/, slot["id"])
    assert_includes slot["url"], "cache/#{slot['id']}", "the URL addresses the slot's own object"
    assert_equal 3, [ exec["uploads"].values, read["uploads"].values ].flatten.pluck("id").uniq.size, "every slot is its own object"
  end

  test "a file over the output cap comes back whole through the upload, and the object is removed" do
    handle = start_session
    big = "log line\n".b * (ContainerRuntime::FakeHostRunner::OUTPUT_CAP / 4)
    @host_runner.machine.container.files["/tmp/terminal_output.log"] = big

    content = @runtime.read_file(handle, "/tmp/terminal_output.log")

    assert_equal big, content
    assert_operator content.bytesize, :>, ContainerRuntime::FakeHostRunner::OUTPUT_CAP
    assert_equal Encoding::BINARY, content.encoding
    id = @host_runner.operations.last[:payload].dig("uploads", "content", "id")
    assert_not Shrine.storages[:cache].exists?(id), "the object is removed once it is read"
    assert RunnerOperation.where(op: "read_file").all? { |op| op.encrypted_payload.nil? }, "the signed URLs leave the payload with the result"
  end

  test "exec output over the output cap comes back whole through the upload" do
    handle = start_session
    cap = ContainerRuntime::FakeHostRunner::OUTPUT_CAP
    # Bytes that are not UTF-8 arrive as U+FFFD, as they do inline.
    out = ("é".b * cap) + "\xFF\n".b + "last line\n".b
    @host_runner.machine.on_exec { [ out, "warn\n", 3 ] }

    stdout, stderr, code = @runtime.exec(handle, [ "cat", "/tmp/big" ])

    assert_equal 3, code
    assert_equal [ "warn\n" ], stderr
    assert_equal "last line\n", stdout.last
    expected = ("é" * cap) + "\uFFFD\n"
    assert_equal expected, stdout.first
    assert_equal Encoding::UTF_8, stdout.first.encoding
    assert stdout.all?(&:valid_encoding?)
    assert_equal 2, stdout.size
  end

  test "a stream under the cap stays inline, and nothing is fetched or removed" do
    handle = start_session
    @host_runner.machine.on_exec { [ "out\n", "", 0 ] }
    Runners::ResultUploads.expects(:claim).never
    Runners::ResultUploads.expects(:discard).never

    assert_equal [ [ "out\n" ], [], 0 ], @runtime.exec(handle, [ "true" ])
  end

  test "a file the runner could not send is nil, as an unreadable file is on hosted" do
    handle = start_session
    @host_runner.answer_with("read_file", "status" => "error",
                                          "error" => { "class" => "file_too_large", "message" => "uploading it failed: 403" })

    assert_nil @runtime.read_file(handle, "/tmp/big")
  end

  test "an upload the result names is claimed only as the slot the platform issued for it" do
    handle = start_session
    @host_runner.answer_with("read_file") do |_payload, _session|
      Shrine.storages[:cache].upload(StringIO.new("other bytes"), "f" * 60)
      { "status" => "ok", "data" => { "size" => 11, "uploads" => { "content" => { "id" => "f" * 60, "size" => 11 } } } }
    end

    assert_nil @runtime.read_file(handle, "/tmp/big"), "an object that is not the slot's own is never read"
    assert Shrine.storages[:cache].exists?("f" * 60), "and never removed"
  end

  test "an upload that is missing, over the limit or of another size is no output, and the exec says so in stderr" do
    handle = start_session
    { "missing" => nil, "mismatch" => "x" * 10, "over the limit" => "x" * 40 }.each do |name, bytes|
      Runners::ResultUploads.stubs(:limit).returns(20)
      claimed_size = name == "mismatch" ? 11 : (bytes&.bytesize || 5)
      @host_runner.answer_with("exec") do |payload, _session|
        slot = payload.dig("uploads", "stdout")
        Shrine.storages[:cache].upload(StringIO.new(bytes), slot["id"]) if bytes
        { "status" => "ok", "exit_code" => 0, "stderr" => "",
          "data" => { "uploads" => { "stdout" => { "id" => slot["id"], "size" => claimed_size } } } }
      end

      stdout, stderr, code = @runtime.exec(handle, [ "cat", "/big" ])

      assert_equal 0, code, name
      assert_empty stdout, name
      assert_match(/upload for stdout/, stderr.join, name)
    end
  end

  test "an op that expired removes the objects of its slots, since the runner may have uploaded before its result was lost" do
    handle = start_session
    uploaded = nil
    @host_runner.answer_with("read_file") do |payload, _session|
      uploaded = payload.dig("uploads", "content", "id")
      Shrine.storages[:cache].upload(StringIO.new("late"), uploaded)
      { "status" => "expired" }
    end

    assert_nil @runtime.read_file(handle, "/tmp/big")

    assert_not_nil uploaded
    assert_not Shrine.storages[:cache].exists?(uploaded)
  end

  test "a storage that cannot be read fails the one output, not the call" do
    handle = start_session
    big = "x".b * (ContainerRuntime::FakeHostRunner::OUTPUT_CAP + 1)
    @host_runner.machine.container.files["/tmp/big"] = big
    Runners::ResultUploads.stubs(:claim).raises(Errno::ECONNRESET)

    assert_nil @runtime.read_file(handle, "/tmp/big")
  end

  # The wait for an op ends at its deadline, inside the activity, so an
  # unanswered reset reaches the machine's failure before the activity ends.
  test "cleanup inside an activity with an unanswered env.reset ends with the machine failed and the reason" do
    handle = start_session
    @host_runner.answer_with("env.reset", :none)

    in_activity(ContainerRuntime::RunnerRuntime::ACTIVITY_MARGIN + 1.0, CleanupProbe, handle)

    @environment.reload
    assert_equal "failed", @environment.state
    assert_nil @environment.current_session_id
    assert_equal "env.reset failed after session #{@session.id}: the runner did not answer", @environment.state_reason
    assert RunnerOperation.find_by(op: "env.reset").expired?
  end

  # As ToolStrategy#wait_with_heartbeat: a stopped session stops waiting at once.
  # CancelProbe does not take Temporal's asynchronous raise, so it is the
  # wait's own check that stops it.
  test "the wait for an op checks the activity's cancellation on every look" do
    handle = start_session
    cancellation, cancel = Temporalio::Cancellation.new
    # The session is stopped once the op is on the queue, and the runner never answers.
    @host_runner.answer_with("status") do
      cancel.call
      :none
    end
    started = Time.current

    assert_raises(Temporalio::Error::CanceledError) do
      in_activity(60.0, CancelProbe, handle, cancellation: cancellation)
    end
    assert_operator Time.current - started, :<, 5, "the wait did not stop at the cancellation"
    assert RunnerOperation.find_by(op: "status").deliverable?, "the op is left to its deadline"
  end

  # Sends one op from inside an activity and reports its deadline.
  class DeadlineProbe < Temporalio::Activity::Definition
    def execute(runtime, id)
      runtime.container_status(id)
      RunnerOperation.order(:id).last.deadline_at
    end
  end

  class CancelProbe < Temporalio::Activity::Definition
    activity_cancel_raise false

    def execute(runtime, id)
      runtime.container_status(id)
    end
  end

  class CleanupProbe < Temporalio::Activity::Definition
    def execute(runtime, id)
      runtime.cleanup_session(id)
      nil
    end
  end

  private

  def spec(session: @session, image: IMAGE, env_vars: [], host_config: {})
    { image: image, env_vars: env_vars, host_config: host_config, privilege_escalation: false,
      labels: { "aixle.session_id" => session.id.to_s } }
  end

  # Creates the session's container, and gives its admission the container's
  # name as AdmittedPhaseActivity does once the create returns.
  def start_session(identify: true)
    handle = @runtime.create_container(spec)
    ContainerRuntime::FakeHostRunner.identify!(@session, handle) if identify
    handle
  end

  def another_session
    create(:runner_session, environment: @environment, runner_environment: nil)
  end

  def in_activity(timeout, activity, id, cancellation: Temporalio::Cancellation.new)
    info = Temporalio::Testing::ActivityEnvironment.default_info.with(started_time: Time.current, start_to_close_timeout: timeout)
    Temporalio::Testing::ActivityEnvironment.new(info: info, cancellation: cancellation,
                                                 activity_executors: TemporalActivityHelper::EXECUTORS)
                                            .run(activity, @runtime, id)
  end
end
