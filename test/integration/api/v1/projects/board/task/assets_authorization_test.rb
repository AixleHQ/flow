# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API task-assets endpoints, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::Task::AssetsPolicy < Web ..::AssetsPolicy):
#   index   (read)  => project_accessible?
#   create  (write) => project_writable?
#   destroy (write) => project_writable?
#     project_writable? == project_accessible? && !current_user.read_only?
# Inaccessible project (stranger / foreign admin) => 404 (current_project is
# resolved via a user-scoped `.find`, which raises RecordNotFound before the
# policy runs). A project has no auto-created board, so the board/column/task
# fixtures are built here. A name-only asset needs no file, so create/destroy
# stay clean 2xx writes with no object-storage (R2) round trip.
class Api::V1::Projects::Board::Task::AssetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_assets_path(@project, @task) }
  end

  test "create is a project write" do
    assert_project_write(transport: :api) do
      post api_v1_project_task_assets_path(@project, @task),
           params: { task_asset: { name: "Authz asset" } }, as: :json
    end
  end

  # destroy mutates, so build a throwaway asset per role iteration.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do
      delete api_v1_project_task_asset_path(@project, @task,
                                            create(:task_asset, board_task: @task, author: @owner)), as: :json
    end
  end
end
