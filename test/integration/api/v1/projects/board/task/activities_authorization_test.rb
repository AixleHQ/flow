# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board-task activities endpoint,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::Task::ActivitiesPolicy < web policy):
#   index? => project_accessible?  (read)
#
# The controller exposes a SINGLE action (index) and it is a plain project read:
# owner/admin/collaborator/viewer are permitted; stranger/foreign admin are scoped
# out to 404 (Project.for_user(...).find raises RecordNotFound before the policy).
# There are no writes, so the viewer (read-only) is permitted on this GET. A project
# has no auto-created board, so the board/column/task fixtures are built here.
class Api::V1::Projects::Board::Task::ActivitiesAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_activities_path(@project, @task) }
  end
end
