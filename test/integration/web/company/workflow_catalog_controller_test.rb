# frozen_string_literal: true

require "test_helper"

class Web::Company::WorkflowCatalogControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders catalog with published workflows" do
    create_list(:workflow, 2, scope: @company, published_at: Time.current, published_by: @user)
    create(:workflow, scope: @company)

    get company_workflow_catalog_index_path
    assert_inertia_page "Company/WorkflowCatalog/IndexPage"
  end

  test "duplicate creates workflow copy in target project" do
    workflow = create(:workflow, scope: @company, published_at: Time.current, published_by: @user)
    create(:step, workflow: workflow, position: 1)
    create(:step, workflow: workflow, position: 2)

    assert_difference "Workflow.count", 1 do
      post duplicate_company_workflow_catalog_path(workflow), params: { project_id: @project.id }
    end

    assert_response :redirect
    copy = Workflow.last
    assert_equal @project.id, copy.scope_id
    assert_equal "Project", copy.scope_type
    assert_equal 2, copy.steps.count
  end

  test "duplicate rejects non-published workflow" do
    workflow = create(:workflow, scope: @company)

    post duplicate_company_workflow_catalog_path(workflow), params: { project_id: @project.id }
    assert_response :redirect
    assert_match(/not found/, flash[:alert])
  end
end
