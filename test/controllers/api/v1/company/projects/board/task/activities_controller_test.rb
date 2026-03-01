# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::Task::ActivitiesControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Dev Board", project: @project)
    @col = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @task = BoardTask.create!(title: "Task 1", board: @board, board_column: @col)
    @task2 = BoardTask.create!(title: "Task 2", board: @board, board_column: @col)
  end

  test "#index returns only task-specific activities" do
    BoardActivity.create!(board: @board, board_task: @task, event_type: :comment_added, actor: @owner, actor_type: :human)
    BoardActivity.create!(board: @board, board_task: @task2, event_type: :comment_added, actor: @owner, actor_type: :human)
    sign_in @owner
    get :index, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success
    assert_equal 1, response.parsed_body["items"].length
  end

  test "#index is paginated" do
    sign_in @owner
    get :index, params: { project_id: @project.id, task_id: @task.id }
    assert_response :success
    assert response.parsed_body["meta"].present?
  end
end
