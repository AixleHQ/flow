# frozen_string_literal: true

require "test_helper"

class Web::Company::WorkflowCatalogRenderTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    Bullet.enable = false # the catalog list page trips the unused-eager-loading gate
    sign_in_as(@user)
  end
  teardown { Bullet.enable = true }

  test "index renders the workflow catalog page" do
    workflow = create(:workflow, scope: @project, published_at: Time.current, published_by: @user)

    get company_workflow_catalog_index_path
    assert_response :success
    assert_inertia_page "Company/WorkflowCatalog/IndexPage"

    assert_inertia_props do |props|
      props[:workflows].any? { |w| w[:id] == workflow.id } &&
        props[:projects].any? { |p| p[:id] == @project.id }
    end
  end
end
