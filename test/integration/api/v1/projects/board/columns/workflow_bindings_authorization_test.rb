# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API column-workflow-binding endpoint,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::Columns::WorkflowBindingsPolicy):
#   show                        => project_accessible?  (read)
#   create / update / destroy   => project_writable?    (write)
# project_writable? == project_accessible? && !read_only?, so the read-only viewer
# passes reads but is denied every mutation (api => 403). current_project is
# resolved via Project.for_user(current_user).find(:project_id), so a project the
# user cannot see raises RecordNotFound (404) before the policy — that is why the
# stranger / foreign admin get 404, not 403.
#
# The binding is a singular resource nested under a board column; a project has no
# auto-created board, so setup builds board + column + a project-scoped workflow
# and a persisted @binding (so an allowed show/update/destroy reaches a real 2xx).
class Api::V1::Projects::Board::Columns::WorkflowBindingsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    # A project-scoped workflow is visible_for_project, satisfying the binding's
    # workflow_accessible_from_project validation for both the fixture and create.
    @workflow = create(:workflow, scope: @project)
    @binding = @column.create_column_workflow_binding!(workflow: @workflow)
  end

  teardown { teardown_authz }

  test "show is a project read" do
    assert_project_read(transport: :api) do
      get api_v1_project_column_workflow_binding_path(@project, @column)
    end
  end

  # board_column_id is unique on column_workflow_binding, so each allowed role must
  # create against a fresh, binding-free column (the matrix runs every allowed role
  # in one transaction — a shared target would collide on the 2nd create). => 201.
  test "create is a project write" do
    assert_project_write(transport: :api) do
      column = create(:board_column, board: @board)
      post api_v1_project_column_workflow_binding_path(@project, column),
           params: { column_workflow_binding: { workflow_id: @workflow.id, trigger_mode: "manual", cooldown_seconds: 5 } },
           as: :json
    end
  end

  # update is idempotent, so allowed roles can all target @column's fixture binding. => 200.
  test "update is a project write" do
    assert_project_write(transport: :api) do
      patch api_v1_project_column_workflow_binding_path(@project, @column),
            params: { column_workflow_binding: { cooldown_seconds: 10 } }, as: :json
    end
  end

  # destroy empties the binding, so each allowed role deletes its own throwaway
  # column's binding (a shared target would 404 on the controller's missing-binding
  # guard for the 2nd role). => 204.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      column = create(:board_column, board: @board)
      column.create_column_workflow_binding!(workflow: @workflow)
      delete api_v1_project_column_workflow_binding_path(@project, column)
    end
  end
end
