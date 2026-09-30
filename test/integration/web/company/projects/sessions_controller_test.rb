# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders the unified sessions and runs page" do
    get company_project_sessions_path(@project)
    assert_inertia_page "Projects/Sessions/SessionsRunsPage"
  end

  test "new renders new session page" do
    get new_company_project_session_path(@project)
    assert_inertia_page "Projects/Sessions/NewPage"
  end

  test "show renders session page" do
    session = create(:terminal_session, :agent_session, user: @user, project: @project)

    get company_project_session_path(@project, session)
    assert_inertia_page "Projects/Sessions/ShowPage"
  end

  test "the run drawer lists workflow steps without counting runs per workflow" do
    workflows = Array.new(3) do |index|
      workflow = create(:workflow, name: "Flow #{index}", scope: @project)
      create(:step, workflow: workflow, name: "Draft #{workflow.name}")
      workflow
    end

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql]
    end

    begin
      get company_project_sessions_path(@project), headers: {
        "X-Inertia" => "true",
        "X-Inertia-Partial-Component" => "Projects/Sessions/SessionsRunsPage",
        "X-Inertia-Partial-Data" => "create_options"
      }
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_response :success
    per_workflow = queries.grep(/FROM "workflow_runs" WHERE "workflow_runs"\."workflow_id" =/)
    assert_empty per_workflow, per_workflow.inspect

    listed = response.parsed_body.dig("props", "createOptions", "workflows").index_by { |workflow| workflow["name"] }
    workflows.each do |workflow|
      steps = listed.fetch(workflow.name).fetch("steps")
      assert_equal [ "Draft #{workflow.name}" ], steps.map { |step| step["name"] }
      assert_not listed[workflow.name].key?("runsCount")
    end
  end
end
