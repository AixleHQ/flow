# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::ConfigItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "index renders config page" do
    get company_project_config_items_path(@project)
    assert_inertia_page "Projects/Config/ConfigPage"
  end

  test "create redirects on success" do
    post company_project_config_items_path(@project), params: {
      config_item: { name: "API_KEY", value: "secret", item_type: "variable" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    item = create(:config_item, scope: @project)

    patch company_project_config_item_path(@project, item), params: {
      config_item: { value: "updated" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    item = create(:config_item, scope: @project)

    delete company_project_config_item_path(@project, item)
    assert_response :redirect
  end
end
