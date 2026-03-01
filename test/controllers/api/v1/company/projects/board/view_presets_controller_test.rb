# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::ViewPresetsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @board = Board.create!(name: "Dev Board", project: @project)
    BoardColumn.create!(name: "Backlog", board: @board, position: 1)
  end

  test "#index returns visible presets" do
    BoardViewPreset.create!(board: @board, user: @owner, name: "My Bugs", filters: { task_type_eq: "bug" })
    BoardViewPreset.create!(board: @board, user: @collaborator, name: "Shared", filters: { a: 1 }, shared: true)
    BoardViewPreset.create!(board: @board, user: @collaborator, name: "Private", filters: { b: 2 })

    sign_in @owner
    get :index, params: { project_id: @project.id }
    assert_response :success
    json = response.parsed_body
    names = json["items"].map { |p| p["name"] }
    assert_includes names, "My Bugs"
    assert_includes names, "Shared"
    assert_not_includes names, "Private"
  end

  test "#create succeeds" do
    sign_in @owner
    post :create, params: {
      project_id: @project.id,
      board_view_preset: { name: "High Priority", filters: { priority_eq: "high" } }
    }
    assert_response :success
    json = response.parsed_body
    assert_equal "High Priority", json.dig("data", "name")
    assert_equal @owner.id, json.dig("data", "user_id")
  end

  test "#create rejects duplicate name" do
    BoardViewPreset.create!(board: @board, user: @owner, name: "Bugs", filters: { a: 1 })
    sign_in @owner
    post :create, params: {
      project_id: @project.id,
      board_view_preset: { name: "Bugs", filters: { b: 2 } }
    }
    assert_response :unprocessable_entity
  end

  test "#destroy own preset" do
    preset = BoardViewPreset.create!(board: @board, user: @collaborator, name: "My Preset", filters: { a: 1 })
    sign_in @collaborator
    assert_difference "BoardViewPreset.count", -1 do
      delete :destroy, params: { project_id: @project.id, id: preset.id }
    end
    assert_response :no_content
  end

  test "#destroy others preset by admin" do
    preset = BoardViewPreset.create!(board: @board, user: @collaborator, name: "Their Preset", filters: { a: 1 })
    sign_in @owner
    assert_difference "BoardViewPreset.count", -1 do
      delete :destroy, params: { project_id: @project.id, id: preset.id }
    end
    assert_response :no_content
  end

  test "#destroy others preset by collaborator is forbidden" do
    preset = BoardViewPreset.create!(board: @board, user: @owner, name: "Owner Preset", filters: { a: 1 })
    sign_in @collaborator
    delete :destroy, params: { project_id: @project.id, id: preset.id }
    assert_response :forbidden
  end
end
