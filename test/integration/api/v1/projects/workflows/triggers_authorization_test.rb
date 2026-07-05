# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the project-scoped Triggers API, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Workflows::TriggersPolicy):
#   index?                       => project_accessible?  (READ)
#   create? / update? / destroy? => project_writable?    (WRITE)
#
# policy_context is a ProjectContext built from
#   current_project = Project.for_user(current_user).find(params[:project_id]),
# so a stranger / foreign-company user is scoped OUT by `for_user`: `.find` raises
# RecordNotFound *before* the policy runs and the api rescue turns it into a 404
# (no existence leak) — hence non-members get 404, not 403. The read-only viewer
# passes project_accessible? but fails project_writable?, so writes 403 (both the
# policy and the deny_read_only_mutation! backstop agree).
#
# The workflow + a slack trigger binding are built here (a project has no
# auto-created workflow/trigger). The seeded binding is a non-schedule (slack)
# kind, so update/destroy on it never enqueues a Temporal schedule reconcile
# (that callback is guarded `if: :schedule?`) — allowed writes stay vendor-free.
class Api::V1::Projects::Workflows::TriggersAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @workflow = create(:workflow, scope: @project)
    @trigger = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @owner)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_workflow_triggers_path(@project, @workflow) }
  end

  # create? gates on project_writable?; an allowed role reaches the action body,
  # which 422s on an unsupported kind before touching any vendor (proof authz
  # passed — not a 403 denial — and no record is created, so the shared fixture
  # stays clean across the role iterations).
  test "create is a project write (allowed roles reach a 422 body guard)" do
    assert_project_write(transport: :api, allowed: :unprocessable_entity) do
      post api_v1_project_workflow_triggers_path(@project, @workflow),
           params: { trigger: { kind: "unsupported" } }, as: :json
    end
  end

  test "update is a project write" do
    assert_project_write(transport: :api) do
      patch api_v1_project_workflow_trigger_path(@project, @workflow, @trigger),
            params: { trigger: { name: "Renamed" } }, as: :json
    end
  end

  # destroy mutates, so build a throwaway (slack) binding per role iteration.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      delete api_v1_project_workflow_trigger_path(
        @project, @workflow,
        create(:trigger_binding, project: @project, workflow: @workflow, created_by: @owner)
      )
    end
  end
end
