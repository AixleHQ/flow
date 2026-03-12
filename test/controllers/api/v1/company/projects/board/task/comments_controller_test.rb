# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::Task::CommentsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @board = Board.create!(name: "Dev Board", project: @project)
    @col = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @task = BoardTask.create!(title: "Test Task", board: @board, board_column: @col)
  end

  # ====== INDEX Tests ======

  test "#index returns comments ordered by created_at desc" do
    TaskComment.create!(body: "First", board_task: @task, author: @owner)
    TaskComment.create!(body: "Second", board_task: @task, author: @owner)
    sign_in @owner

    get :index, params: { project_id: @project.id, task_id: @task.id }

    assert_response :success
    json = response.parsed_body
    assert_equal 2, json["items"].length
    assert_equal "Second", json["items"].first["body"]
  end

  test "#index filters by tag" do
    TaskComment.create!(body: "Bug note", board_task: @task, author: @owner, tags: %w[bug])
    TaskComment.create!(body: "Feature note", board_task: @task, author: @owner, tags: %w[feature])
    sign_in @owner

    get :index, params: { project_id: @project.id, task_id: @task.id, q: { with_tag: "bug" } }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Bug note", json["items"].first["body"]
  end

  test "#index filters by author_type" do
    TaskComment.create!(body: "Human", board_task: @task, author: @owner, author_type: :human)
    TaskComment.create!(body: "Agent", board_task: @task, author: @owner, author_type: :agent)
    sign_in @owner

    get :index, params: { project_id: @project.id, task_id: @task.id, q: { by_author_type: "agent" } }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Agent", json["items"].first["body"]
  end

  test "#index accessible by collaborator" do
    sign_in @collaborator

    get :index, params: { project_id: @project.id, task_id: @task.id }

    assert_response :success
  end

  test "#index not accessible by non-member" do
    sign_in @other_user

    get :index, params: { project_id: @project.id, task_id: @task.id }

    assert_response :forbidden
  end

  # ====== CREATE Tests ======

  test "#create adds comment with current user as author" do
    sign_in @owner

    assert_difference("TaskComment.count") do
      post :create, params: {
        project_id: @project.id,
        task_id: @task.id,
        task_comment: { body: "Great progress!", tags: %w[review] }
      }
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "Great progress!", json["data"]["body"]
    assert_equal @owner.id, json["data"]["author_id"]
    assert_equal "human", json["data"]["author_type"]
    assert_equal %w[review], json["data"]["tags"]
  end

  test "#create accessible by collaborator" do
    sign_in @collaborator

    assert_difference("TaskComment.count") do
      post :create, params: {
        project_id: @project.id,
        task_id: @task.id,
        task_comment: { body: "From collaborator" }
      }
    end

    assert_response :created
  end

  test "#create not accessible by non-member" do
    sign_in @other_user

    assert_no_difference("TaskComment.count") do
      post :create, params: {
        project_id: @project.id,
        task_id: @task.id,
        task_comment: { body: "Hacked" }
      }
    end

    assert_response :forbidden
  end

  test "#create with empty body returns 422" do
    sign_in @owner

    post :create, params: {
      project_id: @project.id,
      task_id: @task.id,
      task_comment: { body: "" }
    }

    assert_response :unprocessable_entity
  end

  # ====== No UPDATE/DELETE endpoints ======

  test "no update endpoint" do
    assert_raises(ActionController::UrlGenerationError) do
      patch :update, params: {
        project_id: @project.id,
        task_id: @task.id,
        id: 1,
        task_comment: { body: "changed" }
      }
    end
  end

  test "no destroy endpoint" do
    assert_raises(ActionController::UrlGenerationError) do
      delete :destroy, params: {
        project_id: @project.id,
        task_id: @task.id,
        id: 1
      }
    end
  end
end
