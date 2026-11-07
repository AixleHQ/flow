# frozen_string_literal: true

require "test_helper"

# A machine whose `env.reset` failed after a session is `failed` (DESIGN.md
# §5.2, task 8a) and held by no session, so nothing that happens to that
# session returns it to rotation: not the release of its admission, not its
# deletion through the API. The launch of the next session on the runner fails
# at once, with the machine and how to bring it back. The real launch path and
# admitted phases, with ContainerRuntime::FakeHostRunner as the machine's host
# runner.
class RunnerFailedMachineTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, email_domain: "test.com")
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @runner = create(:runner, :manual, company: @company, created_by: @user, name: "Build farm")
    @machine = create(:runner_environment, runner: @runner, display_name: "build-01")
    @host_runner = ContainerRuntime::FakeHostRunner.new(@machine)
    stub_container_runtime("kubernetes")
    stub_traefik_http
    stub_container_settings
    with_scope_defaults(project: 4)
    SessionContextService.stubs(:assemble_session_context)
    mock_temporal_start
  end

  teardown do
    @host_runner.stop
    cleanup_runtime_overrides
  end

  test "a machine whose reset failed stays out of rotation after its session is deleted" do
    @host_runner.answer_with("env.reset", "status" => "error",
                                          "error" => { "class" => "reset_failed", "message" => "volume aixle-ws-x is in use" })
    session = launch
    %w[pull_image create_container start_container exec].each { |phase| run_phase(session, phase) }

    cleaned = run_phase(session, "cleanup")

    assert_not cleaned.key?(:cleanup_pending), "cleanup left #{cleaned.inspect}"
    assert session.session_admission.reload.released_at, "the admission is released: the session holds no machine"
    assert_equal "failed", @machine.reload.state
    assert_nil @machine.current_session_id

    sign_in_as(@user)
    delete api_v1_terminal_session_path(session), headers: { "Accept" => "application/json" }
    assert_response :success
    assert_not TerminalSession.exists?(session.id)

    assert_equal "failed", @machine.reload.state, "deleting the session freed nothing"
    @host_runner.operations.clear
    next_session = launch
    assert_equal "failed", next_session.reload.state
    assert_match(/\ARunner "Build farm" has no machine that can take a session: its machine failed: build-01 \(env.reset failed after session #{session.id}: reset_failed: volume aixle-ws-x is in use\)/,
                 next_session.error_message)
    assert_raises(Runners::Machines::NoMachine) do
      Runners::Machines.acquire!(create(:runner_session, environment: @machine, runner_environment: nil))
    end
    assert_empty @host_runner.operations, "nothing reached the failed machine"
  end

  private

  def launch
    with_feature(:external_runners, true, company: @company) do
      SessionService.create_and_start(user: @user, project: @project, session_type: "agent_session",
                                      agent_type: "claude_code",
                                      params: { mode: "non_interactive", initial_prompt: "do something", runner_id: @runner.id })
    end
  end

  def run_phase(session, phase)
    admission = session.session_admission.reload
    activity = Activities::Container::AdmittedPhaseActivity.new
    input = { phase: phase, admission_id: admission.id }
    input[:permit_token] = admission.permit_token unless phase == "cleanup"
    activity.run(Hashie::Mash.new(input))
  end
end
