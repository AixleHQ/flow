# frozen_string_literal: true

require "test_helper"

class Web::Company::WorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders workflows page" do
    create_list(:workflow, 2, scope: @company)

    get company_workflows_path
    assert_inertia_page "Company/Workflows/Index"
  end

  test "builder renders workflow builder" do
    wf = create(:workflow, scope: @company)

    get builder_company_workflow_path(wf)
    assert_inertia_page "Projects/Workflows/BuilderPage"
  end

  test "create redirects on success" do
    post company_workflows_path, params: { workflow: { name: "New WF", description: "D" } }
    assert_response :redirect
  end

  test "destroy redirects on success" do
    wf = create(:workflow, scope: @company)

    delete company_workflow_path(wf)
    assert_response :redirect
  end
end
