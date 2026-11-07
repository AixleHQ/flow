# frozen_string_literal: true

require "test_helper"

# A non-interactive session on a `manual` runner runs on the runner's machine
# through the op queue (DESIGN.md §5.3, §15 task 8a): the real launch
# (SessionService → admission → launch relay) and the admitted container
# phases (AdmittedPhaseActivity), with ContainerRuntime::FakeHostRunner as the
# machine's host runner. Every runtime call of the strategy is one op, and the
# hosted runtime is never asked anything.
class RunnerSessionLaunchTest < ActiveSupport::TestCase
  IMAGE = "ghcr.io/aixlehq/flow-claude-code@sha256:#{'b' * 64}".freeze

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
    assert_equal %w[image.ensure container.start status write_file exec], @host_runner.ops
    assert_equal({ "image" => "ghcr.io/aixlehq/flow-claude-code", "digest" => "sha256:#{'b' * 64}" },
                 @host_runner.operations.first[:payload])
    assert_equal ContainerStrategies::AgentSessionStrategy::PROMPT_PATH, @host_runner.operations.fourth[:payload]["path"]
    start = @host_runner.operations.second
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
    run_phases(first, %w[pull_image])
    second = launch

    assert_equal({ "capacity_wait" => true }, run_phase(second, "pull_image"))
    assert_match(/Waiting for a free machine on runner "Build farm" \(1 of 1 busy\)/,
                 second.session_admission.reload.last_error)

    run_phases(first, %w[create_container start_container exec cleanup])
    run_phases(second, %w[pull_image])

    assert_equal @machine.id, second.reload.runner_environment_id
    assert_equal second.id, @machine.reload.current_session_id
  end

  test "a runner with no machine fails the launch with the message that names it" do
    @machine.update!(state: :gone)

    session = launch

    assert_equal "failed", session.reload.state
    assert_equal "Runner \"Build farm\" has no machine registered. Register a machine on it, or pick another runner " \
                 "for the session.", session.error_message
    assert_empty @host_runner.operations
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
