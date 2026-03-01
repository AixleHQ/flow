# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::Columns::WorkflowBindingControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @board = Board.create!(name: "Dev Board", project: @project)
    @column = BoardColumn.create!(name: "In Progress", board: @board, position: 1)
    @workflow = Workflow.create!(name: "CI Pipeline", scope: @project)
  end

  test "#show returns 404 when no binding" do
    sign_in @owner
    get :show, params: { project_id: @project.id, column_id: @column.id }
    assert_response :not_found
  end

  test "#show returns binding" do
    ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow)
    sign_in @owner
    get :show, params: { project_id: @project.id, column_id: @column.id }
    assert_response :success
    json = response.parsed_body
    assert_equal @workflow.id, json.dig("data", "workflow_id")
    assert_equal @workflow.name, json.dig("data", "workflow_name")
  end

  test "#create succeeds for admin" do
    sign_in @owner
    post :create, params: {
      project_id: @project.id,
      column_id: @column.id,
      column_workflow_binding: {
        workflow_id: @workflow.id,
        trigger_mode: "auto",
        cooldown_seconds: 10
      }
    }
    assert_response :success
    json = response.parsed_body
    assert_equal "auto", json.dig("data", "trigger_mode")
    assert_equal 10, json.dig("data", "cooldown_seconds")
  end

  test "#update changes trigger mode" do
    ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow, trigger_mode: :manual)
    sign_in @owner
    patch :update, params: {
      project_id: @project.id,
      column_id: @column.id,
      column_workflow_binding: { trigger_mode: "auto" }
    }
    assert_response :success
    assert_equal "auto", @column.column_workflow_binding.reload.trigger_mode
  end

  test "#destroy removes binding" do
    ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow)
    sign_in @owner
    assert_difference "ColumnWorkflowBinding.count", -1 do
      delete :destroy, params: { project_id: @project.id, column_id: @column.id }
    end
    assert_response :no_content
  end

  test "#create fails for collaborator" do
    sign_in @collaborator
    post :create, params: {
      project_id: @project.id,
      column_id: @column.id,
      column_workflow_binding: { workflow_id: @workflow.id }
    }
    assert_response :forbidden
  end

  test "#create rejects inaccessible workflow" do
    other_company = create(:company, email_domain: "other.com")
    other_project = create(:project, company: other_company, owner: create(:user, :employee, company: other_company))
    other_wf = Workflow.create!(name: "Other", scope: other_project)
    sign_in @owner
    post :create, params: {
      project_id: @project.id,
      column_id: @column.id,
      column_workflow_binding: { workflow_id: other_wf.id }
    }
    assert_response :unprocessable_entity
  end
end
