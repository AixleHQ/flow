# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::BoardsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)
  end

  # ====== SHOW Tests ======

  test "#show returns board when exists" do
    board = Board.create!(name: "Dev Board", project: @project)
    sign_in @owner

    get :show, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    assert_equal board.id, json["data"]["id"]
    assert_equal "Dev Board", json["data"]["name"]
  end

  test "#show returns 404 when no board exists" do
    sign_in @owner

    get :show, params: { project_id: @project.id }

    assert_response :not_found
  end

  test "#show accessible by collaborator" do
    Board.create!(name: "Board", project: @project)
    sign_in @collaborator

    get :show, params: { project_id: @project.id }

    assert_response :success
  end

  test "#show not accessible by non-member" do
    Board.create!(name: "Board", project: @project)
    sign_in @other_user

    get :show, params: { project_id: @project.id }

    assert_response :forbidden
  end

  test "#show requires authentication" do
    get :show, params: { project_id: @project.id }

    assert_response :unauthorized
  end

  # ====== CREATE Tests ======

  test "#create creates board for project" do
    sign_in @owner

    assert_difference("Board.count") do
      post :create, params: {
        project_id: @project.id,
        board: { name: "Sprint Board" }
      }
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "Sprint Board", json["data"]["name"]
    assert_nil json["data"]["preset_origin"]
  end

  test "#create returns 422 when board already exists" do
    Board.create!(name: "Existing", project: @project)
    sign_in @owner

    post :create, params: {
      project_id: @project.id,
      board: { name: "Duplicate" }
    }

    assert_response :unprocessable_entity
  end

  test "#create not accessible by collaborator" do
    sign_in @collaborator

    assert_no_difference("Board.count") do
      post :create, params: {
        project_id: @project.id,
        board: { name: "Board" }
      }
    end

    assert_response :forbidden
  end

  test "#create not accessible by non-member" do
    sign_in @other_user

    assert_no_difference("Board.count") do
      post :create, params: {
        project_id: @project.id,
        board: { name: "Board" }
      }
    end

    assert_response :forbidden
  end

  # ====== CREATE with Preset Tests ======

  test "#create with preset creates board and columns" do
    sign_in @owner

    assert_difference("Board.count") do
      post :create, params: {
        project_id: @project.id,
        board: { preset: "dev_team" }
      }
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "Dev Team", json["data"]["name"]
    assert_equal "dev_team", json["data"]["preset_origin"]
    assert_equal 7, json["data"]["board_columns"].size
  end

  test "#create with preset and custom name" do
    sign_in @owner

    post :create, params: {
      project_id: @project.id,
      board: { preset: "simple_kanban", name: "My Kanban" }
    }

    assert_response :created
    json = response.parsed_body
    assert_equal "My Kanban", json["data"]["name"]
    assert_equal "simple_kanban", json["data"]["preset_origin"]
  end

  test "#create with invalid preset returns 422" do
    sign_in @owner

    post :create, params: {
      project_id: @project.id,
      board: { preset: "nonexistent" }
    }

    assert_response :unprocessable_entity
  end

  # ====== PRESETS Tests ======

  test "#presets returns available preset definitions" do
    sign_in @owner

    get :presets, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    keys = json.map { |p| p["key"] }
    assert_includes keys, "simple_kanban"
    assert_includes keys, "dev_team"
    assert_includes keys, "full_sdlc"
  end

  test "#presets accessible by collaborator" do
    sign_in @collaborator

    get :presets, params: { project_id: @project.id }

    assert_response :success
  end

  test "#presets not accessible by non-member" do
    sign_in @other_user

    get :presets, params: { project_id: @project.id }

    assert_response :forbidden
  end

  # ====== UPDATE Tests ======

  test "#update updates board name" do
    board = Board.create!(name: "Old Name", project: @project)
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      board: { name: "New Name" }
    }

    assert_response :success
    board.reload
    assert_equal "New Name", board.name
  end

  test "#update returns 404 when no board" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      board: { name: "Name" }
    }

    assert_response :not_found
  end

  test "#update not accessible by collaborator" do
    Board.create!(name: "Board", project: @project)
    sign_in @collaborator

    patch :update, params: {
      project_id: @project.id,
      board: { name: "Hacked" }
    }

    assert_response :forbidden
  end

  # ====== DESTROY Tests ======

  test "#destroy removes board" do
    Board.create!(name: "Board", project: @project)
    sign_in @owner

    assert_difference("Board.count", -1) do
      delete :destroy, params: { project_id: @project.id }
    end

    assert_response :no_content
  end

  test "#destroy returns 404 when no board" do
    sign_in @owner

    delete :destroy, params: { project_id: @project.id }

    assert_response :not_found
  end

  test "#destroy not accessible by collaborator" do
    Board.create!(name: "Board", project: @project)
    sign_in @collaborator

    assert_no_difference("Board.count") do
      delete :destroy, params: { project_id: @project.id }
    end

    assert_response :forbidden
  end

  test "#destroy not accessible by non-member" do
    Board.create!(name: "Board", project: @project)
    sign_in @other_user

    assert_no_difference("Board.count") do
      delete :destroy, params: { project_id: @project.id }
    end

    assert_response :forbidden
  end
end
