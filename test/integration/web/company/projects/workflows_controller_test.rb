# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::WorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders project workflows page" do
    create_list(:workflow, 2, scope: @project)

    get company_project_workflows_path(@project)
    assert_inertia_page "Projects/Workflows/WorkflowsPage"
  end

  test "builder renders workflow builder" do
    wf = create(:workflow, scope: @project)

    get builder_company_project_workflow_path(@project, wf)
    assert_inertia_page "Projects/Workflows/BuilderPage"
  end

  test "create redirects on success" do
    post company_project_workflows_path(@project), params: { workflow: { name: "Proj WF", description: "D" } }
    assert_response :redirect
  end

  test "destroy redirects on success" do
    wf = create(:workflow, scope: @project)

    delete company_project_workflow_path(@project, wf)
    assert_response :redirect
  end

  test "publish sets published_at on project workflow" do
    wf = create(:workflow, scope: @project)

    post publish_company_project_workflow_path(@project, wf)
    assert_response :redirect

    wf.reload
    assert wf.published?
  end

  test "duplicate creates a copy in same project" do
    wf = create(:workflow, scope: @project, name: "Original")
    create(:step, workflow: wf, position: 1)

    assert_difference "Workflow.count", 1 do
      post duplicate_company_project_workflow_path(@project, wf)
    end

    assert_response :redirect
  end
end
