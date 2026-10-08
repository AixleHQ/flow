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

  # update is stricter than a plain project write: beyond the project_writable?
  # policy the controller enforces the record-level rules — the editor must be the
  # comment's own author, the comment must be human-authored, and younger than
  # TaskComment::EDIT_WINDOW (TaskComment#editable_by?). Those are not expressible
  # in the shared read/write matrix (admin/collaborator are writers but not the
  # author), so they are asserted explicitly here.
  test "owner can edit their own fresh human comment" do
    comment = create(:task_comment, board_task: @task, author: @owner, author_type: :human)
    sign_in_as(@owner)
    patch api_v1_project_task_comment_path(@project, @task, comment),
          params: { task_comment: { body: "Edited" } }, as: :json
    assert_response :success
    assert_equal "Edited", comment.reload.body
  end

  test "a non-author collaborator cannot edit someone else's comment" do
    comment = create(:task_comment, board_task: @task, author: @owner, author_type: :human)
    original = comment.body
    sign_in_as(@collaborator)
    patch api_v1_project_task_comment_path(@project, @task, comment),
          params: { task_comment: { body: "Hijack" } }, as: :json
    assert_response :forbidden
    assert_equal original, comment.reload.body
  end

  test "the read-only viewer cannot edit a comment" do
    comment = create(:task_comment, board_task: @task, author: @viewer, author_type: :human)
    sign_in_as(@viewer)
    patch api_v1_project_task_comment_path(@project, @task, comment),
          params: { task_comment: { body: "Edited" } }, as: :json
    assert_response :forbidden
  end

  test "an agent-authored comment cannot be edited" do
    comment = create(:task_comment, board_task: @task, author: @owner, author_type: :agent)
    sign_in_as(@owner)
    patch api_v1_project_task_comment_path(@project, @task, comment),
          params: { task_comment: { body: "Edited" } }, as: :json
    assert_response :forbidden
  end

  test "a comment older than the edit window cannot be edited" do
    comment = create(:task_comment, board_task: @task, author: @owner, author_type: :human)
    comment.update_column(:created_at, (TaskComment::EDIT_WINDOW + 1.minute).ago)
    sign_in_as(@owner)
    patch api_v1_project_task_comment_path(@project, @task, comment),
          params: { task_comment: { body: "Edited" } }, as: :json
    assert_response :forbidden
  end

  test "update does not change tags or author_type" do
    comment = create(:task_comment, board_task: @task, author: @owner, author_type: :human, tags: %w[bug])
    sign_in_as(@owner)
    patch api_v1_project_task_comment_path(@project, @task, comment),
          params: { task_comment: { body: "Edited", tags: %w[feature], author_type: "agent" } }, as: :json
    assert_response :success
    comment.reload
    assert_equal "Edited", comment.body
    assert_equal %w[bug], comment.tags
    assert_equal "human", comment.author_type
  end
end
