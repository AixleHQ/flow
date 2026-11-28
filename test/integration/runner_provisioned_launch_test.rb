# frozen_string_literal: true

require "test_helper"

# A session on a runner whose environments the platform makes
# (docs/design/agent-runtimes/runner-coder.md §5.1, §10), through the real launch
# and the admitted container phases, with a fake provisionable adapter. What the
# platform answers to a session that has to wait for its environment, and to one
# whose environment cannot be made, is the same on every runtime: only a lack of
# capacity waits, and anything else fails the phase and runs the cleanup
# (docs/architecture/runtime-layers.md, guarantees 1 and 2).
class RunnerProvisionedLaunchTest < ActiveSupport::TestCase
  setup do
    @company = create(:company, email_domain: "test.com")
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @runner = create(:runner, :coder, company: @company, created_by: @user, name: "Cloud farm", max_environments: 2)
    @adapter = with_fake_provisioned_adapter
    @hosted = stub_container_runtime("kubernetes")
    stub_traefik_http
    stub_container_settings
    with_scope_defaults(project: 4)
    SessionContextService.stubs(:assemble_session_context)
    mock_temporal_start
  end

  teardown do
    cleanup_runtime_overrides
  end

  test "a session whose environment is being built waits as runner_provisioning, with its reservation kept" do
    session = launch
    run_phases(session, %w[pull_image])

    assert_equal({ "capacity_wait" => true }, run_phase(session, "create_container"))

    admission = session.session_admission.reload
    assert_equal "runner_provisioning", admission.wait_reason
    assert_equal "runner_provisioning", admission.launch_phase
    assert_match(/\AStarting an environment on runner "Cloud farm" \(provisioning\)/, admission.last_error)
    assert_includes SessionAdmission.waiting.pluck(:id), admission.id
    assert_nil admission.released_at
    environment = RunnerEnvironment.where(runner: @runner).sole
    assert_equal session.id, environment.current_session_id

    # The retry, 30 s later, advances the same environment.
    assert_equal({ "capacity_wait" => true }, run_phase(session, "create_container"))
    assert_equal "booting", environment.reload.state
    assert_equal 1, RunnerEnvironment.where(runner: @runner).count
  end

  test "an integration with nothing to give is a capacity wait with its own message, and no environment gets a machine" do
    @adapter.exhausted = "The integration has no capacity left."
    session = launch
    run_phases(session, %w[pull_image])

    assert_equal({ "capacity_wait" => true }, run_phase(session, "create_container"))

    admission = session.session_admission.reload
    assert_equal "runner_capacity", admission.wait_reason
    assert_equal "The integration has no capacity left.", admission.last_error
    assert_nil RunnerEnvironment.where(runner: @runner).sole.external_id
  end

  test "an environment that cannot be made fails the phase as non-retryable and runs the cleanup, which releases the admission" do
    @adapter.provision_error = "The template needs a parameter."
    session = launch
    run_phases(session, %w[pull_image])

    error = assert_raises(Temporalio::Error::ApplicationError) { run_phase(session, "create_container") }

    assert_includes error.message, "The template needs a parameter."
    admission = session.session_admission.reload
    assert_equal "retryable", admission.session_runtime_operations.find_by!(phase: "create_container").state,
                 "the platform refused the create: nothing was dispatched to pin"
    environment = RunnerEnvironment.where(runner: @runner).sole
    assert_equal "failed", environment.state
    assert_equal "The template needs a parameter.", environment.state_reason

    cleaned = run_phase(session, "cleanup", error: "The template needs a parameter.")

    assert_not cleaned.key?(:cleanup_pending), "cleanup left #{cleaned.inspect}"
    assert admission.reload.released_at
    assert_equal "failed", session.reload.state
  end

  test "a runner at its limit of environments leaves the next session waiting for a machine, not for a build" do
    create_list(:runner_environment, 2, :allocated, runner: @runner, state: "tearing_down")
    session = launch
    run_phases(session, %w[pull_image])

    assert_equal({ "capacity_wait" => true }, run_phase(session, "create_container"))

    assert_equal "runner_capacity", session.session_admission.reload.wait_reason
    assert_match(/at its limit of 2 environments/, session.session_admission.last_error)
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

  def run_phase(session, phase, error: nil)
    admission = session.session_admission.reload
    activity = Activities::Container::AdmittedPhaseActivity.new
    if phase == "cleanup"
      activity.run(Hashie::Mash.new(phase: phase, admission_id: admission.id, error: error))
    else
      activity.run(Hashie::Mash.new(phase: phase, admission_id: admission.id, permit_token: admission.permit_token))
    end
  end
end
