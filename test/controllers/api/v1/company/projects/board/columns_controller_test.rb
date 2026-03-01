# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::ColumnsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @board = Board.create!(name: "Dev Board", project: @project)
    @col1 = BoardColumn.create!(name: "Backlog", board: @board, position: 1, purpose: "Waiting")
    @col2 = BoardColumn.create!(name: "In Progress", board: @board, position: 2, purpose: "Active")
    @col3 = BoardColumn.create!(name: "Done", board: @board, position: 3, purpose: "Completed")
  end

  # ====== INDEX Tests ======

  test "#index returns all columns ordered by position" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    names = json["items"].map { |c| c["name"] }
    assert_equal %w[Backlog In\ Progress Done], names
  end

  test "#index accessible by collaborator" do
    sign_in @collaborator

    get :index, params: { project_id: @project.id }

    assert_response :success
  end

  test "#index not accessible by non-member" do
    sign_in @other_user

    get :index, params: { project_id: @project.id }

    assert_response :forbidden
  end

  test "#index returns 404 when no board" do
    project2 = create(:project, company: @company, owner: @owner)
    sign_in @owner

    get :index, params: { project_id: project2.id }

    assert_response :not_found
  end

  # ====== SHOW Tests ======

  test "#show returns single column" do
    sign_in @owner

    get :show, params: { project_id: @project.id, id: @col1.id }

    assert_response :success
    json = response.parsed_body
    assert_equal "Backlog", json["data"]["name"]
    assert_equal "Waiting", json["data"]["purpose"]
  end

  # ====== CREATE Tests ======

  test "#create adds column with auto-position" do
    sign_in @owner

    assert_difference("BoardColumn.count") do
      post :create, params: {
        project_id: @project.id,
        board_column: { name: "Review", purpose: "Code review stage" }
      }
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "Review", json["data"]["name"]
    assert_equal 4, json["data"]["position"]
  end

  test "#create not accessible by collaborator" do
    sign_in @collaborator

    assert_no_difference("BoardColumn.count") do
      post :create, params: {
        project_id: @project.id,
        board_column: { name: "New" }
      }
    end

    assert_response :forbidden
  end

  # ====== UPDATE Tests ======

  test "#update changes column name and purpose" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @col1.id,
      board_column: { name: "Todo", purpose: "Updated purpose" }
    }

    assert_response :success
    @col1.reload
    assert_equal "Todo", @col1.name
    assert_equal "Updated purpose", @col1.purpose
  end

  test "#update not accessible by collaborator" do
    sign_in @collaborator

    patch :update, params: {
      project_id: @project.id,
      id: @col1.id,
      board_column: { name: "Hacked" }
    }

    assert_response :forbidden
  end

  # ====== DESTROY Tests ======

  test "#destroy removes column and compacts positions" do
    sign_in @owner

    assert_difference("BoardColumn.count", -1) do
      delete :destroy, params: { project_id: @project.id, id: @col2.id }
    end

    assert_response :no_content
    @col1.reload
    @col3.reload
    assert_equal 1, @col1.position
    assert_equal 2, @col3.position
  end

  test "#destroy not accessible by collaborator" do
    sign_in @collaborator

    assert_no_difference("BoardColumn.count") do
      delete :destroy, params: { project_id: @project.id, id: @col1.id }
    end

    assert_response :forbidden
  end

  # ====== REORDER Tests ======

  test "#reorder updates positions" do
    sign_in @owner

    patch :reorder, params: {
      project_id: @project.id,
      column_ids: [ @col3.id, @col1.id, @col2.id ]
    }

    assert_response :success
    @col1.reload
    @col2.reload
    @col3.reload
    assert_equal 2, @col1.position
    assert_equal 3, @col2.position
    assert_equal 1, @col3.position
  end

  test "#reorder not accessible by collaborator" do
    sign_in @collaborator

    patch :reorder, params: {
      project_id: @project.id,
      column_ids: [ @col3.id, @col1.id, @col2.id ]
    }

    assert_response :forbidden
  end

  test "#reorder not accessible by non-member" do
    sign_in @other_user

    patch :reorder, params: {
      project_id: @project.id,
      column_ids: [ @col3.id, @col1.id, @col2.id ]
    }

    assert_response :forbidden
  end
end
