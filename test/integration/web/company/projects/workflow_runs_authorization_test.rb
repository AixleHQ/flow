# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped WorkflowRuns
# controller, via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Web::Company::Projects::WorkflowRunsPolicy < Web::Company::ApplicationPolicy):
#   index? / show?  => project_accessible?  (read)
#   create?         => project_writable?    (write)
#   cancel? / approve_step? / retry_step? / skip_step?
#                   => project_writable? AND WorkflowRun#controllable_by? — the
#                      run's own user, or a company admin. A collaborator who
#                      could otherwise write is refused, with a flash naming the
#                      person whose run it is instead of the generic denial.
#
# All routes are web (html). Denied viewer => 302 + denial alert; stranger /
# foreign admin => 404 (the project is scoped out via Project.for_user(...).find
# while authorize builds the policy context, before the action body runs).
#
# create and cancel are given an intentionally missing workflow_id / run id, so
# the ALLOWED roles reach a deterministic RecordNotFound (404) INSIDE the action
# body — after authorization has already passed, and before any Temporal call.
# That still proves authorization (a denied role never reaches the body) without
# stubbing or actually starting/cancelling a Temporal workflow (WorkflowService
# .start hits Temporal only after run.save; WorkflowService.cancel signals it
# unconditionally). approve_step / retry_step / skip_step use a real run with no
# active step, so the controller skips the WorkflowService (Temporal) call and
# just redirects — a genuine, vendor-free allowed-write outcome.
class Web::Company::Projects::WorkflowRunsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @run = create(:workflow_run, project: @project, user: @owner)
  end

  teardown { teardown_authz }

  # Still a project read, but the action now redirects into the unified
  # Sessions & Runs list instead of rendering — every role that could read the
  # old list gets the redirect, and the ones that could not are still scoped out.
  test "index is a project read that redirects to the unified list" do
    assert_role_matrix(project_read_expectations, transport: :web, allowed_status: :redirect) do
      get company_project_workflow_runs_path(@project)
    end
  end

  test "show is a project read" do
    assert_project_read { get company_project_workflow_run_path(@project, @run) }
  end

  # Missing workflow_id => allowed roles reach a RecordNotFound (404) before
  # WorkflowService.start (and thus before Temporal); viewer is still denied.
  test "create is a project write (allowed roles reach a 404 guard before Temporal)" do
    assert_project_write(allowed: :not_found) do
      post company_project_workflow_runs_path(@project), params: { workflow_run: { workflow_id: 0 } }
    end
  end

  # Nonexistent run id => allowed roles reach a RecordNotFound (404) before
  # WorkflowService.cancel signals Temporal; viewer is still denied. A run that
  # does not exist carries no owner, so the ownership gate stays out of the way
  # and this is still the plain write matrix.
  test "cancel is a project write (allowed roles reach a 404 guard before Temporal)" do
    assert_project_write(allowed: :not_found) do
      post cancel_company_project_workflow_run_path(@project, 0)
    end
  end

  # The run has no current step, so the controller skips WorkflowService and just
  # redirects (clean 302) — a vendor-free allowed write.
  test "approve_step is a run-control write" do
    assert_run_control_matrix { post approve_step_company_project_workflow_run_path(@project, @run) }
  end

  test "retry_step is a run-control write" do
    assert_run_control_matrix { post retry_step_company_project_workflow_run_path(@project, @run) }
  end

  test "skip_step is a run-control write" do
    assert_run_control_matrix { post skip_step_company_project_workflow_run_path(@project, @run) }
  end

  test "cancel on someone else's run is refused before Temporal is signalled" do
    sign_in_as(@collaborator)

    post cancel_company_project_workflow_run_path(@project, @run)

    assert_redirected_to company_project_workflow_run_path(@project, @run)
    assert_match(/only they or a company admin can control it/, flash[:alert])
    assert_equal "pending", @run.reload.state
  end

  private

  # Writes that steer a run: the run's user (@owner) and company admins pass;
  # a collaborator who may otherwise write is refused with the ownership flash
  # rather than the generic denial, so it is asserted outside the matrix.
  def assert_run_control_matrix(&block)
    expectations = {
      owner: :allowed_write, admin: :allowed_write,
      viewer: :denied, stranger: :not_found, foreign_admin: :not_found
    }
    assert_role_matrix(expectations, transport: :web, &block)

    sign_in_as(@collaborator)
    instance_exec(:collaborator, &block)
    assert_response :redirect
    assert_match(/only they or a company admin can control it/, flash[:alert])
  end
end
