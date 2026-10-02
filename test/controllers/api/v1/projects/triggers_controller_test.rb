# frozen_string_literal: true

require "test_helper"

class Api::V1::Projects::TriggersControllerTest < ActionController::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :onboarding_completed, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @column = create(:board_column, board: create(:board, project: @project), name: "Inbox")
    @intake = create(:workflow, scope: @project, name: "Intake")
    @release = create(:workflow, scope: @project, name: "Release")
    sign_in @user
  end

  def json
    JSON.parse(response.body)
  end

  test "index lists the triggers of every live workflow of the project, each with its workflow" do
    ColumnWorkflowBinding.create!(board_column: @column, workflow: @intake, created_by: @user)
    create(:trigger_binding, project: @project, workflow: @release, created_by: @user, event_type: "slack.message")
    archived = create(:workflow, scope: @project, name: "Old")
    create(:trigger_binding, project: @project, workflow: archived, created_by: @user, event_type: "slack.message")
    archived.update_columns(deleted_at: Time.current)
    other = create(:project, company: @company, owner: @user)
    create(:trigger_binding, project: other, workflow: create(:workflow, scope: other), created_by: @user, event_type: "slack.message")

    get :index, params: { project_id: @project.id }

    assert_response :success
    assert_equal [ [ "column", "board", "Intake" ], [ "slack", "chat", "Release" ] ],
                 json["triggers"].map { |t| t.values_at("kind", "source", "workflow_name") }
  end

  test "a project the user is not in is not found" do
    stranger = create(:user, :onboarding_completed, company: create(:company))
    sign_in stranger

    get :index, params: { project_id: @project.id }

    assert_response :not_found
  end
end
