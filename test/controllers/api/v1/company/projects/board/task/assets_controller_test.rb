# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::Task::AssetsControllerTest < ActionController::TestCase
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

  test "#index returns assets" do
    TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @owner)
    sign_in @owner

    get :index, params: { project_id: @project.id, task_id: @task.id }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "doc.pdf", json["items"].first["name"]
  end

  test "#index filters by tag" do
    TaskAsset.create!(name: "design.png", board_task: @task, author: @owner, tags: %w[design])
    TaskAsset.create!(name: "code.rb", board_task: @task, author: @owner, tags: %w[code])
    sign_in @owner

    get :index, params: { project_id: @project.id, task_id: @task.id, tag: "design" }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "design.png", json["items"].first["name"]
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

  test "#create adds asset with current user as author" do
    sign_in @owner

    assert_difference("TaskAsset.count") do
      post :create, params: {
        project_id: @project.id,
        task_id: @task.id,
        task_asset: { name: "screenshot.png", tags: %w[ui] }
      }
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "screenshot.png", json["data"]["name"]
    assert_equal @owner.id, json["data"]["author_id"]
    assert_equal "human", json["data"]["author_type"]
    assert_equal %w[ui], json["data"]["tags"]
  end

  test "#create accessible by collaborator" do
    sign_in @collaborator

    assert_difference("TaskAsset.count") do
      post :create, params: {
        project_id: @project.id,
        task_id: @task.id,
        task_asset: { name: "file.txt" }
      }
    end

    assert_response :created
  end

  test "#create not accessible by non-member" do
    sign_in @other_user

    assert_no_difference("TaskAsset.count") do
      post :create, params: {
        project_id: @project.id,
        task_id: @task.id,
        task_asset: { name: "hacked.txt" }
      }
    end

    assert_response :forbidden
  end

  # ====== DESTROY Tests ======

  test "#destroy by admin (owner) succeeds" do
    asset = TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @collaborator)
    sign_in @owner

    assert_difference("TaskAsset.count", -1) do
      delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: asset.id }
    end

    assert_response :no_content
  end

  test "#destroy by author succeeds" do
    asset = TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @collaborator)
    sign_in @collaborator

    assert_difference("TaskAsset.count", -1) do
      delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: asset.id }
    end

    assert_response :no_content
  end

  test "#destroy by non-author collaborator forbidden" do
    other_collab = create(:user, :employee, company: @company)
    @project.add_collaborator(other_collab)
    asset = TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @collaborator)
    sign_in other_collab

    assert_no_difference("TaskAsset.count") do
      delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: asset.id }
    end

    assert_response :forbidden
  end

  test "#destroy not accessible by non-member" do
    asset = TaskAsset.create!(name: "doc.pdf", board_task: @task, author: @owner)
    sign_in @other_user

    assert_no_difference("TaskAsset.count") do
      delete :destroy, params: { project_id: @project.id, task_id: @task.id, id: asset.id }
    end

    assert_response :forbidden
  end
end
