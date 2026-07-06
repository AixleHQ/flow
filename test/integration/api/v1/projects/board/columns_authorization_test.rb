# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board-columns endpoints, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::ColumnsPolicy):
#   reads  (index/show)                    => project_accessible?
#   writes (create/update/destroy/reorder) => project_writable?
# The API policy overrides the web policy's project_admin? writes down to plain
# project_writable?, so an employee collaborator (not just the owner/admin) may
# mutate columns — the standard project write matrix. The read-only viewer is
# denied (403) and inaccessible-project users (stranger / foreign admin) are
# scoped out to 404 by Project.for_user(...).find before the policy runs.
#
# A project has no auto-created board, so the board + a column are built here.
class Api::V1::Projects::Board::ColumnsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_columns_path(@project) }
  end

  test "show is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_column_path(@project, @column) }
  end

  test "create is a project write" do
    assert_project_write(transport: :api) do
      post api_v1_project_columns_path(@project),
           params: { board_column: { name: "Authz Column", purpose: "Doing" } }, as: :json
    end
  end

  test "update is a project write" do
    assert_project_write(transport: :api) do
      patch api_v1_project_column_path(@project, @column),
            params: { board_column: { name: "Renamed" } }, as: :json
    end
  end

  test "reorder is a project write" do
    assert_project_write(transport: :api) do
      patch reorder_api_v1_project_columns_path(@project), params: { column_ids: [ @column.id ] }, as: :json
    end
  end

  # destroy mutates, so build a throwaway (task-free) column per role iteration.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      delete api_v1_project_column_path(@project, create(:board_column, board: @board))
    end
  end
end
