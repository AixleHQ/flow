# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board-task transitions endpoint,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# The controller exposes a SINGLE action:
#   index (GET /api/v1/projects/:project_id/tasks/:task_id/transitions)
#
# Policy (Api::V1::Projects::Board::Task::TransitionsPolicy < web TransitionsPolicy
# < Web::Company::ApplicationPolicy):
#   index? => project_accessible?   (read)
# There are NO write actions, so index is a pure project read: owner/admin/
# collaborator/viewer are permitted (the viewer is a collaborator and index is a
# GET, so the read-only-mutation backstop does not apply), while strangers and
# foreign-company admins are scoped out to 404 (Project.for_user(current_user)
# .find raises RecordNotFound before the policy). A project has no auto-created
# board, so the board/column/task fixtures the task-nested route requires are
# built here (current_board raises RecordNotFound without a board).
class Api::V1::Projects::Board::Task::TransitionsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board  = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task   = create(:board_task, board: @board, board_column: @column)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_transitions_path(@project, @task) }
  end
end
