# frozen_string_literal: true

require "test_helper"

# A session's runner (DESIGN.md §3.3, §3.4): the pick on the new-session form or
# the API for a standalone session, the run's for a workflow step.
class SessionServiceRunnerTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    @runner = create(:runner, company: @company, created_by: @user, name: "Prod VPC")
  end

  test "a standalone session on a runner is saved, then failed before admission with the message" do
    session = with_feature(:external_runners, true, company: @company) { create_session(runner_id: @runner.id) }

    assert session.persisted?
    assert_equal "failed", session.reload.state
    assert_equal @runner.id, session.runner_id
    assert_equal "Runner \"Prod VPC\" can't take sessions yet: runner execution not enabled.", session.error_message
    assert_nil session.session_admission
  end

  test "a disabled runner fails the session with what to do" do
    @runner.disable!

    session = with_feature(:external_runners, true, company: @company) { create_session(runner_id: @runner.id) }

    assert_equal "Runner \"Prod VPC\" is disabled. Re-enable it or pick another runner for the session.",
                 session.reload.error_message
  end

  test "without the flag the pick is refused and nothing is saved" do
    session = with_feature(:external_runners, false, company: @company) { create_session(runner_id: @runner.id) }

    assert_not session.persisted?
    assert_equal [ "External runners are not enabled for this company." ], session.errors.full_messages
    assert_equal 0, TerminalSession.count
  end

  test "an interactive session cannot pick a runner yet" do
    session = with_feature(:external_runners, true, company: @company) do
      create_session(runner_id: @runner.id, mode: "interactive", initial_prompt: nil)
    end

    assert_not session.persisted?
    assert_equal [ "Runner \"Prod VPC\" can't run interactive sessions yet." ], session.errors.full_messages
  end

  test "a session without a pick is hosted and admitted as before" do
    mock_temporal_start

    session = with_feature(:external_runners, true, company: @company) { create_session }

    assert_nil session.runner_id
    assert session.session_admission.present?
    assert_not_equal "failed", session.reload.state
  end

  test "a step on a refused runner raises before its session is built" do
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, :running, workflow: workflow, project: @project, user: @user, runner: @runner)
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))

    refusal = with_feature(:external_runners, true, company: @company) do
      assert_raises(Runners::Resolver::Refused) { SessionService.create_for_workflow_step(step_run: step_run) }
    end

    assert_equal "runner_execution_not_enabled", refusal.reason
    assert_nil step_run.reload.terminal_session
    assert_equal 0, TerminalSession.count
  end

  test "a hosted step's session runs hosted" do
    mock_temporal_start
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))

    session = with_feature(:external_runners, true, company: @company) do
      SessionService.create_for_workflow_step(step_run: step_run)
    end

    assert_nil session.runner_id
    assert_equal "acknowledged", session.session_admission.launch_state
  end

  private

  def create_session(mode: "non_interactive", initial_prompt: "do it", **params)
    SessionService.create_and_start(
      user: @user, project: @project, session_type: "agent_session", agent_type: "claude_code",
      params: ActionController::Parameters.new({ mode: mode, initial_prompt: initial_prompt, **params }).permit!
    )
  end
end
