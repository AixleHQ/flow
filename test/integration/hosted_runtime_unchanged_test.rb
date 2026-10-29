# frozen_string_literal: true

require "test_helper"

# DESIGN.md §12.3: turning external_runners on for a company changes nothing for
# its hosted sessions. The same hosted admission and launch run twice, once with
# the flag off and once with it on for the session's company, through the real
# SessionService → SessionAdmissionService → SessionLaunchRelay path and the
# admitted container phases (AdmittedPhaseActivity) on the runtime seam that
# KubernetesRuntime sits behind (ContainerRuntime::FakeRuntime). Both runs must
# make the same runtime calls and leave the same admission.
class HostedRuntimeUnchangedTest < ActiveSupport::TestCase
  setup do
    @company = create(:company, email_domain: "test.com")
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    stub_traefik_http
    stub_container_settings
    with_scope_defaults(project: 4)
    Settings.stubs(:container_runtime).returns("kubernetes")
    SessionContextService.stubs(:assemble_session_context)
    mock_temporal_start
    mock_workflow_execution_start
  end

  teardown { cleanup_runtime_overrides }

  test "a standalone hosted session is admitted and launched the same with the flag on" do
    off = trace { launch_standalone }
    on = with_feature(:external_runners, true, company: @company) { trace { launch_standalone } }

    assert_equal off, on
    assert_equal "finished", on[:state]
  end

  test "a hosted workflow step is admitted and launched the same with the flag on" do
    off = trace { launch_step }
    on = with_feature(:external_runners, true, company: @company) { trace { launch_step } }

    assert_equal off, on
    assert_equal "finished", on[:state]
  end

  private

  def launch_standalone
    SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code",
      params: { mode: "non_interactive", initial_prompt: "do something" }
    )
  end

  def launch_step
    workflow = create(:workflow, scope: @project)
    create(:step, workflow: workflow, instructions: "do something")
    run = WorkflowService.start(workflow: workflow, project: @project, user: @user, source: :web)
    SessionService.create_for_workflow_step(step_run: run.step_runs.sole)
  end

  # Ids, tokens and timestamps differ between two sessions; everything else the
  # runtime is asked to do must not.
  def trace
    runtime = stub_container_runtime("kubernetes", agent_type: "claude_code")
    session = yield
    launch_state = session.session_admission.reload.launch_state
    run_phases(session)
    admission = session.session_admission.reload

    {
      runner_id: session.runner_id,
      launch_state: launch_state,
      admission: admission.slice(:runtime_kind, :wait_reason).merge(
        "pool" => admission.session_admission_pool.key, "released" => admission.released_at.present?
      ).transform_values { |v| normalize(v) },
      execs: runtime.execs.map { |cmd| normalize(Array(cmd).join(" ")) },
      uploads: runtime.uploads.map { |upload| normalize(upload.inspect) },
      written: runtime.written_paths.map { |path| normalize(path) },
      cleaned: runtime.cleaned_sessions.map { |id| normalize(id) },
      state: session.reload.state
    }
  end

  # The phases the hosted container workflow runs for an admitted session.
  def run_phases(session)
    admission = session.session_admission.reload
    activity = Activities::Container::AdmittedPhaseActivity.new
    %w[pull_image create_container start_container exec].each do |phase|
      activity.run(Hashie::Mash.new(phase: phase, admission_id: admission.id, permit_token: admission.permit_token))
    end
    activity.run(Hashie::Mash.new(phase: "cleanup", admission_id: admission.id))
  end

  def normalize(value)
    value.to_s.gsub(/\h{12,}/, "<hex>").gsub(/[A-Za-z0-9_-]{32,}/, "<token>").gsub(/\d+/, "<n>")
  end
end
