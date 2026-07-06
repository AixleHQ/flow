# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API task-statistics endpoint, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::Task::StatisticsPolicy):
#   show => project_accessible?   (the ONLY action; it is a read)
#
# There is no mutation action here, so the read-only viewer collaborator is
# PERMITTED (reads map to project_accessible?, not project_writable?). The
# stranger / foreign admin are scoped out by Project.for_user(...).find before
# the policy runs, so they get 404 (not 403). A project has no auto-created
# board, so the board/column/task fixtures are built here.
class Api::V1::Projects::Board::Task::StatisticsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  teardown { teardown_authz }

  test "show is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_statistics_path(@project, @task) }
  end
end
