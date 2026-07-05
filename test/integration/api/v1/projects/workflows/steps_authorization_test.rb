# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API project-workflow-steps endpoints,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Workflows::StepsPolicy < Web::Company::Projects::Workflows::StepsPolicy):
#   reads  (index/show)                     => project_accessible?
#   writes (create/update/destroy/reorder)  => project_writable?
#     project_writable? == project_accessible? && !current_user.read_only?
# So reads use the project-read matrix (owner/admin/collaborator/viewer allowed;
# stranger/foreign scoped out => 404) and writes use the project-write matrix
# (owner/admin/collaborator allowed; the read-only viewer denied => 403;
# stranger/foreign scoped out => 404). The project is resolved via
# Project.for_user(current_user).find in the before_action, so an inaccessible
# project raises RecordNotFound (404) before the policy runs.
#
# The nested workflow + one step are built in setup. Writes send minimal valid
# bodies so the allowed roles clear the action body and reach 2xx rather than
# erroring for a non-authorization reason. Because the harness reruns the
# allowed-write block once per allowed role inside one transaction, `create`
# derives a per-role position (the [workflow_id, position] index is unique and
# `save!` is unrescued) and `destroy` deletes a throwaway step created in the
# block (the factory sequences position, so no collision).
class Api::V1::Projects::Workflows::StepsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @workflow = create(:workflow, scope: @project)
    @step = create(:step, workflow: @workflow)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_workflow_steps_path(@project, @workflow) }
  end

  test "show is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_workflow_step_path(@project, @workflow, @step) }
  end

  # A distinct position per allowed role keeps every create clear of the
  # [workflow_id, position] unique index (the block reruns per role in one txn).
  test "create is a project write" do
    assert_project_write(transport: :api) do |role|
      post api_v1_project_workflow_steps_path(@project, @workflow),
           params: { step: { name: "Authz step (#{role})", position: 1000 + AuthorizationMatrix::ROLES.index(role) } },
           as: :json
    end
  end

  test "update is a project write" do
    assert_project_write(transport: :api) do
      patch api_v1_project_workflow_step_path(@project, @workflow, @step),
            params: { step: { name: "Authz Renamed Step" } }, as: :json
    end
  end

  # reorder passes a real {step_id => position} map so params.require(:positions)
  # and the update loop succeed for allowed roles.
  test "reorder is a project write" do
    assert_project_write(transport: :api) do
      patch reorder_api_v1_project_workflow_steps_path(@project, @workflow),
            params: { positions: { @step.id.to_s => "1" } }, as: :json
    end
  end

  # destroy mutates, so delete a throwaway step per role iteration (the factory
  # sequences position, so no collision) and keep @step for the other tests.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      delete api_v1_project_workflow_step_path(@project, @workflow, create(:step, workflow: @workflow))
    end
  end
end
