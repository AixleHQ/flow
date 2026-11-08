# frozen_string_literal: true

require "test_helper"

# A non-interactive session on a `manual` runner runs on the runner's machine
# through the op queue (DESIGN.md §5.3, §15 task 8a): the real launch
# (SessionService → admission → launch relay) and the admitted container
# phases (AdmittedPhaseActivity), with ContainerRuntime::FakeHostRunner as the
# machine's host runner. Every runtime call of the strategy is one op, and the
# hosted runtime is never asked anything.
class RunnerSessionLaunchTest < ActiveSupport::TestCase
  IMAGE = "ghcr.io/aixlehq/flow-claude-code:latest"

  setup do
    @company = create(:company, email_domain: "test.com")
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @runner = create(:runner, :manual, company: @company, created_by: @user, name: "Build farm")
    @machine = create(:runner_environment, runner: @runner, key: "aixle-r#{@runner.id}-0a1b2c3d")
    @host_runner = ContainerRuntime::FakeHostRunner.new(@machine)
    @hosted = stub_container_runtime("kubernetes")
    stub_traefik_http
    stub_container_settings
    with_scope_defaults(project: 4)
    SessionContextService.stubs(:assemble_session_context)
    mock_temporal_start
    @previous_image = Settings.agents.images[:claude_code]
    Settings.agents.images[:claude_code] = IMAGE
  end

  teardown do
    Settings.agents.images[:claude_code] = @previous_image
    @host_runner.stop
    cleanup_runtime_overrides
  end

  test "a session on a manual runner runs on its machine, one op per runtime call, and frees the machine" do
    session = launch
    admission = session.session_admission.reload

    run_phases(session, %w[pull_image create_container start_container exec])

    session.reload
    assert_equal "ready", session.state
    assert_equal @machine.id, session.runner_environment_id
    assert_equal "aixle-#{@machine.key}-#{session.id}", session.container_id
    assert_equal "ContainerRuntime::RunnerRuntime", admission.reload.runtime_kind
    assert_equal %w[container.start status write_file exec], @host_runner.ops
    start = @host_runner.operations.first
    assert_equal IMAGE, start[:payload]["image"], "the image as it was given, by tag, which container.start pulls"
    assert_equal [ IMAGE ], @host_runner.machine.images
    assert_equal ContainerStrategies::AgentSessionStrategy::PROMPT_PATH, @host_runner.operations.third[:payload]["path"]
    assert_equal({ "cpus" => 2.0, "memory_bytes" => 4096.megabytes, "pids_limit" => 4096 }, start[:payload]["resources"],
                 "the hosted container's limits")
    assert_equal session.id.to_s, start[:payload]["env"]["SESSION_ID"]

    cleaned = run_phase(session, "cleanup")

    assert_not cleaned.key?(:cleanup_pending), "cleanup left #{cleaned.inspect}"
    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2)
    assert_equal "finished", session.reload.state
    assert_nil @machine.reload.current_session_id, "the machine is free after its reset"
    assert admission.reload.released_at
    assert_ops_name_their_session(session)
    assert RunnerOperation.all.none?(&:deliverable?)
    assert RunnerOperation.all.all? { |op| op.encrypted_payload.nil? }, "a finished op's payload is nulled"
    assert_empty @hosted.execs, "the hosted runtime ran nothing"
    assert_empty @hosted.cleaned_sessions
  end

  test "a second session waits while the machine is busy, and takes it once the first is done" do
    first = launch
    run_phases(first, %w[pull_image create_container])
    second = launch
    run_phases(second, %w[pull_image])

    assert_equal({ "capacity_wait" => true }, run_phase(second, "create_container"))
    assert_match(/Waiting for a free machine on runner "Build farm" \(1 of 1 busy\)/,
                 second.session_admission.reload.last_error)

    run_phases(first, %w[start_container exec cleanup])
    run_phases(second, %w[create_container])

    assert_equal @machine.id, second.reload.runner_environment_id
    assert_equal second.id, @machine.reload.current_session_id
  end

  test "a pull that fails in container.start still runs the cleanup, which resets the machine and frees it" do
    @host_runner.answer_with("container.start", "status" => "error",
                                                "error" => { "class" => "image_pull_failed", "message" => "pull access denied" })
    session = launch
    run_phases(session, %w[pull_image])

    assert_raises(Temporalio::Error::ApplicationError) { run_phase(session, "create_container") }
    admission = session.session_admission.reload
    assert_equal "runner-session-#{session.id}", admission.runtime_id, "the identity was persisted before the create"
    assert_equal session.id, @machine.reload.current_session_id
    cleaned = run_phase(session, "cleanup")

    assert_not cleaned.key?(:cleanup_pending), "cleanup left #{cleaned.inspect}"
    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2)
    assert_nil @machine.reload.current_session_id, "the machine is free again"
    assert admission.reload.released_at
  end

  # The runner runs a machine's ops one at a time, in order, so a cleanup op
  # queued behind an unfinished `container.start` would expire behind it.
  test "a stop while container.start is unanswered sends the cleanup only once the start has its answer" do
    cancellation, cancel = Temporalio::Cancellation.new
    # The session is stopped once the start is on the queue, and the runner is still pulling.
    @host_runner.answer_with("container.start") do
      cancel.call
      :none
    end
    session = launch
    run_phases(session, %w[pull_image])

    assert_raises(Temporalio::Error) { run_phase_in_activity(session, "create_container", cancellation) }
    start = RunnerOperation.find_by!(op: "container.start")
    assert start.deliverable?, "nothing answered the start"

    assert run_phase(session, "cleanup")[:cleanup_pending], "the cleanup waits for the start"
    assert_equal %w[container.start], @host_runner.ops, "nothing is queued behind the start"

    # The runner answers late: the pull ended within the start's deadline, and the container runs.
    container = @host_runner.machine.start(session.id, @host_runner.operations.first[:payload])
    Runners::Operations.record_result!(start, status: "ok",
                                              result: { "data" => { "container_id" => container.id, "name" => container.name } })
    run_phase(session, "cleanup")

    assert_equal "container.start", @host_runner.ops.first
    assert_equal %w[container.stop env.reset], @host_runner.ops.last(2), "the cleanup ran after the start's answer"
    assert_nil @host_runner.machine.container, "the late start's container is gone"
    @machine.reload
    assert_equal [ "registered", nil ], [ @machine.state, @machine.current_session_id ], "the machine is free"
  end

  test "a start the runner refused releases the admission at once: nothing of the create can appear later" do
    %w[container_start_failed volume_not_owned].each do |klass|
      @host_runner.answer_with("container.start", "status" => "error", "error" => { "class" => klass, "message" => "refused" })
      session = launch
      run_phases(session, %w[pull_image])

      assert_raises(Temporalio::Error::ApplicationError, klass) { run_phase(session, "create_container") }
      cleaned = run_phase(session, "cleanup")

      assert_not cleaned.key?(:cleanup_pending), "#{klass}: cleanup left #{cleaned.inspect}"
      assert session.session_admission.reload.released_at, "#{klass}: the admission is released"
      assert_nil @machine.reload.current_session_id, "#{klass}: the machine is free"
    end
  end

  test "a machine unregistered during a session stops holding it, and the session's cleanup releases its admission" do
    session = launch
    run_phases(session, %w[pull_image create_container start_container exec])
    admission = session.session_admission.reload
    runtime = ContainerRuntime.for_session(session)
    @host_runner.operations.clear

    Runners::Registration.unregister!(@machine)

    assert_nil @machine.reload.current_session_id
    assert runtime.session_absent?(admission.runtime_id)
    assert_equal :missing, runtime.container_status(admission.runtime_id), "its ops answer as a container that is gone"
    cleaned = run_phase(session, "cleanup")
    assert_not cleaned.key?(:cleanup_pending), "cleanup left #{cleaned.inspect}"
    assert admission.reload.released_at
    assert_empty @host_runner.operations, "nothing is sent to a machine that left"
  end

  test "a stop between the pull and the create takes no machine, and the cleanup sends nothing" do
    session = launch
    run_phases(session, %w[pull_image])
    assert_nil @machine.reload.current_session_id, "the machine is taken in create_container"

    SessionAdmissionService.cancel!(session)
    assert_raises(Temporalio::Error::ApplicationError) { run_phase(session, "create_container") }
    cleaned = run_phase(session, "cleanup")

    assert_not cleaned.key?(:cleanup_pending), "cleanup left #{cleaned.inspect}"
    assert_empty @host_runner.operations
    assert_nil @machine.reload.current_session_id
    assert session.session_admission.reload.released_at
    assert_equal "cancelled", session.reload.state, "stopped before it was ever ready"
  end

  test "a runner with no machine fails the launch with the message that names it" do
    @machine.update!(state: :gone)

    session = launch

    assert_equal "failed", session.reload.state
    assert_equal "Runner \"Build farm\" has no machine registered. Register a machine on it, or pick another runner " \
                 "for the session.", session.error_message
    assert_empty @host_runner.operations
  end

  # Runners::Machines::NoMachine is raised before any op exists, so the create
  # is never dispatched: the cleanup releases the admission at once, with no
  # absence window (AdmittedPhaseActivity::NEVER_DISPATCHED).
  test "a machine lost between the launch and the create fails with the runner's message and releases the admission at once" do
    session = launch
    run_phases(session, %w[pull_image])
    Runners::Machines.fail!(@machine, "lost after the launch")

    error = assert_raises(Temporalio::Error::ApplicationError) { run_phase(session, "create_container") }
    assert_includes error.message, "Runner \"Build farm\" has no machine that can take a session"
    admission = session.session_admission.reload
    assert_equal "retryable", admission.session_runtime_operations.find_by!(phase: "create_container").state,
                 "no op was dispatched, so the create pins nothing"

    cleaned = run_phase(session, "cleanup")

    assert_not cleaned.key?(:cleanup_pending), "cleanup left #{cleaned.inspect}"
    assert admission.reload.released_at, "the admission is released at once"
    assert_empty @host_runner.operations, "nothing was sent to the runner"
  end

  test "the scanners and the live log read a runner session through its machine, not the hosted runtime" do
    session = launch
    run_phases(session, %w[pull_image create_container start_container exec])
    session.update_columns(started_at: 1.hour.ago)
    @host_runner.machine.exit!(137, oom_killed: true)
    @host_runner.operations.clear

    Activities::Session::ScanDeadContainersActivity.new.run
    tail = Sessions::LiveLogReader.new(session.reload).tail(lines: 10)

    assert_equal %w[status exec], @host_runner.ops
    assert_equal :unreachable, tail.status
    assert session.reload.metadata.key?(Activities::Session::ScanDeadContainersActivity::MARKER_KEY),
           "a dead runner container is seen as dead"
    assert_empty @hosted.execs
  end

  test "a hosted session in the same company stays on the hosted runtime" do
    session = with_feature(:external_runners, true, company: @company) do
      SessionService.create_and_start(user: @user, project: @project, session_type: "agent_session",
                                      agent_type: "claude_code",
                                      params: { mode: "non_interactive", initial_prompt: "do something" })
    end

    run_phases(session, %w[pull_image create_container start_container exec cleanup])

    assert_nil session.reload.runner_environment_id
    assert_empty @host_runner.operations
    assert @hosted.execs.any?
    assert_equal "finished", session.state
  end

  # Does not take Temporal's asynchronous raise, so it is the op wait's own
  # cancellation check that stops the phase.
  class PhaseProbe < Temporalio::Activity::Definition
    activity_cancel_raise false

    def execute(input)
      Activities::Container::AdmittedPhaseActivity.new.run(Hashie::Mash.new(input))
    end
  end

  private

  def launch
    with_feature(:external_runners, true, company: @company) do
      SessionService.create_and_start(user: @user, project: @project, session_type: "agent_session",
                                      agent_type: "claude_code",
                                      params: { mode: "non_interactive", initial_prompt: "do something", runner_id: @runner.id })
    end
  end

  def run_phases(session, phases)
    phases.each { |phase| run_phase(session, phase) }
  end

  def run_phase(session, phase)
    admission = session.session_admission.reload
    activity = Activities::Container::AdmittedPhaseActivity.new
    if phase == "cleanup"
      activity.run(Hashie::Mash.new(phase: phase, admission_id: admission.id))
    else
      activity.run(Hashie::Mash.new(phase: phase, admission_id: admission.id, permit_token: admission.permit_token))
    end
  end

  # Runs a phase inside an activity, whose cancellation the op wait checks.
  def run_phase_in_activity(session, phase, cancellation)
    admission = session.session_admission.reload
    info = Temporalio::Testing::ActivityEnvironment.default_info.with(started_time: Time.current, start_to_close_timeout: 600.0)
    Temporalio::Testing::ActivityEnvironment.new(info: info, cancellation: cancellation,
                                                 activity_executors: TemporalActivityHelper::EXECUTORS)
                                            .run(PhaseProbe, { phase: phase, admission_id: admission.id,
                                                               permit_token: admission.permit_token })
  end

  def assert_ops_name_their_session(session)
    RunnerOperation.order(:sequence).each do |operation|
      if RunnerOperation::ENVIRONMENT_OPS.include?(operation.op)
        assert_nil operation.terminal_session_id, "#{operation.op} is an environment op and names no session"
      else
        assert_equal session.id, operation.terminal_session_id, "#{operation.op} names the wrong session"
      end
    end
  end
end
