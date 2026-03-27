# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::PaladBuilderControllerTest < ActionController::TestCase
  setup do
    @company = create(:company)
    @admin = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @admin)

    # Ensure meta tools exist
    Tool.find_or_create_by!(name: "meta_create_workflow", kind: :workflow) do |t|
      t.display_name = "Meta Create Workflow"
      t.execution_mode = :app
      t.input_schema = {}
    end
  end

  test "#start creates a terminal session with meta tools" do
    sign_in @admin

    SessionService.expects(:create_and_start).with(
      user: @admin,
      project: @project,
      session_type: "agent_session",
      agent_type: "claude_code",
      params: has_entries(mode: "interactive", tool_ids: instance_of(Array))
    ).returns(create(:terminal_session, user: @admin, project: @project))

    post :start, params: { project_id: @project.id, agent_runtime: "claude_code" }
    assert_response :success
  end

  test "#start uses default agent runtime when not specified" do
    sign_in @admin

    SessionService.expects(:create_and_start).with(
      user: @admin,
      project: @project,
      session_type: "agent_session",
      agent_type: anything,
      params: has_entries(mode: "interactive")
    ).returns(create(:terminal_session, user: @admin, project: @project))

    post :start, params: { project_id: @project.id }
    assert_response :success
  end

  test "#status returns palad builder sessions" do
    sign_in @admin

    session = create(:terminal_session, user: @admin, project: @project,
                     initial_prompt: "# Palad Builder\nYou are a Workflow Architect...")

    get :status, params: { project_id: @project.id }
    assert_response :success
    body = response.parsed_body
    ids = (body["items"] || []).map { |s| s["id"] }
    assert_includes ids, session.id
  end
end
