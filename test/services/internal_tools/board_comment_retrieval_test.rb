# frozen_string_literal: true

require "test_helper"

class InternalTools::BoardCommentRetrievalTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: @task)
    step_run = create(:step_run, workflow_run: run, step: create(:step, workflow: workflow))
    @session = create(:terminal_session, :agent_session, user: @user, project: @project, step_run: step_run)
  end

  test "pages deterministically through equal timestamps without hiding an older decision" do
    older = create(:task_comment, board_task: @task, author: @user, body: "Approved contract", created_at: 1.day.ago)
    first = create(:task_comment, board_task: @task, author: @user, body: "First", created_at: 1.hour.ago)
    second = create(:task_comment, board_task: @task, author: @user, body: "Second", created_at: first.created_at)

    page = list(limit: 2)
    assert_equal [ second.id, first.id ], page["comments"].map { |comment| comment["id"] }
    assert_equal 3, page["total"]
    assert page["has_more"]
    last = list(limit: 2, offset: 2)
    assert_equal [ older.id ], last["comments"].map { |comment| comment["id"] }
    assert_equal false, last["has_more"] # rubocop:disable Minitest/RefuteFalse
  end

  test "previews declare truncation and the same comment can be read in full" do
    body = ("Background. " * 100) + "MUST preserve /billing"
    comment = create(:task_comment, board_task: @task, author: @user, body: body)
    preview = list["comments"].first

    assert_equal comment.id, preview["id"]
    assert preview["body_truncated"]
    assert_equal body.length, preview["body_length"]
    assert_operator preview["body"].length, :<=, 400
    full = InternalTools::BoardGetComment.new(params: { task_id: @task.id, comment_id: comment.id }, session: @session).execute
    assert_equal 0, full[:exit_code]
    assert_equal body, JSON.parse(full[:stdout])["body"]
  end

  test "filters are applied before counting and paging with the human alias preserved" do
    create(:task_comment, board_task: @task, author: @user, body: "Decision", author_type: :human, tags: [ "approved" ])
    create(:task_comment, board_task: @task, author: @user, body: "Proposal", author_type: :agent, tags: [ "approved" ])
    create(:task_comment, board_task: @task, author: @user, body: "Other human note")

    %w[human user].each do |type|
      page = list(author_type: type, tag: "approved")
      assert_equal 1, page["total"]
      assert_equal [ "Decision" ], page["comments"].map { |comment| comment["body"] }
    end
  end

  test "caps page size and returns an explicit empty last page" do
    page = list(limit: 10_000, offset: -5)
    assert_equal 100, page["limit"]
    assert_equal 0, page["offset"]
    assert_equal 0, page["total"]
    assert_empty page["comments"]
    assert_equal false, page["has_more"] # rubocop:disable Minitest/RefuteFalse
    assert_equal 25, list["limit"]
  end

  test "cannot list another board or read a comment belonging to a different task" do
    board = create(:board, project: create(:project, company: @company, owner: @user))
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    comment = create(:task_comment, board_task: task, author: @user, body: "Private decision")

    result = InternalTools::BoardListComments.new(params: { task_id: task.id }, session: @session).execute
    assert_equal 1, result[:exit_code]
    result = InternalTools::BoardGetComment.new(params: { task_id: @task.id, comment_id: comment.id }, session: @session).execute
    assert_equal 1, result[:exit_code]
    assert_not_includes result[:stdout], "Private decision"
  end

  private

  def list(**params)
    result = InternalTools::BoardListComments.new(params: { task_id: @task.id }.merge(params), session: @session).execute
    assert_equal 0, result[:exit_code]
    JSON.parse(result[:stdout])
  end
end
