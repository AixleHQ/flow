# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board-tasks endpoints, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::TasksPolicy):
#   reads  (index/show/workflow_runs)                     => project_accessible?
#   writes (create/update/destroy/move/trigger_workflow)  => project_writable?
# Inaccessible project (stranger / foreign admin) => 404 (scoped `.find` raises
# RecordNotFound before the policy). A project has no auto-created board, so the
# board/column/task fixtures are built here.
class Api::V1::Projects::Board::TasksAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_tasks_path(@project) }
  end

  test "show is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_path(@project, @task) }
  end

  test "workflow_runs is a project read" do
    assert_project_read(transport: :api) { get workflow_runs_api_v1_project_task_path(@project, @task) }
  end

  test "create is a project write" do
    assert_project_write(transport: :api) do
      post api_v1_project_tasks_path(@project),
           params: { board_task: { title: "Authz task", board_column_id: @column.id } }, as: :json
    end
  end

  test "update is a project write" do
    assert_project_write(transport: :api) do
      patch api_v1_project_task_path(@project, @task), params: { board_task: { title: "Renamed" } }, as: :json
    end
  end

  test "move is a project write" do
    assert_project_write(transport: :api) do
      patch move_api_v1_project_task_path(@project, @task), params: { column_id: @column.id, position: 1 }, as: :json
    end
  end

  # destroy mutates, so build a throwaway task per role iteration.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      delete api_v1_project_task_path(@project, create(:board_task, board: @board, board_column: @column))
    end
  end

  # No workflow binding on the column, so an allowed role passes authorization
  # and reaches the action body, which returns 422 (evidence authz passed, not
  # a 403 denial).
  test "trigger_workflow is a project write (allowed roles reach a 422 guard)" do
    assert_project_write(transport: :api, allowed: :unprocessable_entity) do
      post trigger_workflow_api_v1_project_task_path(@project, @task), as: :json
    end
  end

  test "bulk_actions is a project write" do
    assert_project_write(transport: :api) do
      post bulk_actions_api_v1_project_tasks_path(@project),
           params: { action_type: "delete", task_ids: [ @task.id ] }, as: :json
    end
  end
end
