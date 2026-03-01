# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::Task::TransitionsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: create(:company, email_domain: "other.com"))

    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Dev Board", project: @project)
    @col1 = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @col2 = BoardColumn.create!(name: "Done", board: @board, position: 2)
    @task = BoardTask.create!(title: "Test Task", board: @board, board_column: @col1)
  end

  test "#index returns transitions for task" do
    ColumnTransition.create!(board_task: @task, from_column: @col1, to_column: @col2, actor: @owner, actor_type: :human)
    sign_in @owner
    get :index, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal @col1.id, json["items"][0]["from_column_id"]
    assert_equal @col2.id, json["items"][0]["to_column_id"]
  end

  test "#index is ordered desc by created_at" do
    t1 = ColumnTransition.create!(board_task: @task, from_column: @col1, to_column: @col2, actor: @owner, actor_type: :human)
    t2 = ColumnTransition.create!(board_task: @task, from_column: @col2, to_column: @col1, actor: @owner, actor_type: :agent)
    sign_in @owner
    get :index, params: { project_id: @project.id, task_id: @task.id }
    ids = response.parsed_body["items"].map { |t| t["id"] }
    assert_equal [ t2.id, t1.id ], ids
  end

  test "#index forbidden for non-member" do
    sign_in @other_user
    get :index, params: { project_id: @project.id, task_id: @task.id }
    assert_includes [ 403, 404 ], response.status
  end
end
