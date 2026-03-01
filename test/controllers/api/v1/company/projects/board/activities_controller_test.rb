# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::ActivitiesControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @other = create(:user, :employee, company: create(:company, email_domain: "other.com"))

    @project = create(:project, company: @company, owner: @owner)
    @board = Board.create!(name: "Dev Board", project: @project)
    @col = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @task = BoardTask.create!(title: "Task 1", board: @board, board_column: @col)
  end

  test "#index returns paginated activities" do
    3.times { |i| BoardActivity.create!(board: @board, board_task: @task, event_type: :task_created, actor: @owner, actor_type: :human, metadata: { title: "Task #{i}" }) }
    sign_in @owner
    get :index, params: { project_id: @project.id }
    assert_response :success
    json = response.parsed_body
    assert_equal 3, json["items"].length
    assert json["meta"].present?
  end

  test "#index filters by event_type" do
    BoardActivity.create!(board: @board, event_type: :task_created, actor: @owner, actor_type: :human)
    BoardActivity.create!(board: @board, event_type: :task_moved, actor: @owner, actor_type: :human)
    sign_in @owner
    get :index, params: { project_id: @project.id, event_type: "task_created" }
    assert_response :success
    assert_equal 1, response.parsed_body["items"].length
  end

  test "#index filters by actor_type" do
    BoardActivity.create!(board: @board, event_type: :task_created, actor: @owner, actor_type: :human)
    BoardActivity.create!(board: @board, event_type: :task_moved, actor: @owner, actor_type: :agent)
    sign_in @owner
    get :index, params: { project_id: @project.id, actor_type: "agent" }
    assert_equal 1, response.parsed_body["items"].length
  end

  test "#index filters by since" do
    old = BoardActivity.create!(board: @board, event_type: :task_created, actor: @owner, actor_type: :human)
    old.update_column(:created_at, 3.days.ago)
    BoardActivity.create!(board: @board, event_type: :task_moved, actor: @owner, actor_type: :human)
    sign_in @owner
    get :index, params: { project_id: @project.id, since: 1.day.ago.iso8601 }
    assert_equal 1, response.parsed_body["items"].length
  end

  test "#index includes description in serializer" do
    BoardActivity.create!(board: @board, board_task: @task, event_type: :task_created, actor: @owner, actor_type: :human, metadata: { title: "Task 1" })
    sign_in @owner
    get :index, params: { project_id: @project.id }
    item = response.parsed_body["items"][0]
    assert item["description"].present?
    assert item["actor_name"].present?
  end

  test "#index forbidden for non-member" do
    sign_in @other
    get :index, params: { project_id: @project.id }
    assert_includes [ 403, 404 ], response.status
  end
end
