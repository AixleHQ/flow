# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API task-comments endpoints, via the
# shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::Task::CommentsPolicy < Web::Company::Projects::
#         Board::Task::CommentsPolicy < Web::Company::ApplicationPolicy):
#   index  (read)  => project_accessible?
#   create (write) => project_writable? (== project_accessible? && !read_only?)
# Inaccessible project (stranger / foreign admin) => 404: current_project resolves
# through Project.for_user(current_user).find(:project_id), so a project the user
# cannot see raises RecordNotFound before the policy runs. A project has no
# auto-created board, so the board/column/task fixtures are built here. The allowed
# create sends a minimal valid body ({task_comment: {body:}}) so TaskService.
# add_comment (a plain DB insert, no vendors/Temporal) completes and returns 2xx.
class Api::V1::Projects::Board::Task::CommentsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board  = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task   = create(:board_task, board: @board, board_column: @column)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_task_comments_path(@project, @task) }
  end

  test "create is a project write" do
    assert_project_write(transport: :api) do
      post api_v1_project_task_comments_path(@project, @task),
           params: { task_comment: { body: "Authz comment" } }, as: :json
    end
  end
end
