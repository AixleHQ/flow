# frozen_string_literal: true

require "test_helper"

class Web::Company::ConfigItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders config items page" do
    get company_config_items_path
    assert_inertia_page "Company/ConfigItems/Index"
  end

  test "create redirects on success" do
    post company_config_items_path, params: {
      config_item: { name: "MY_VAR", value: "val", item_type: "variable" }
    }
    assert_response :redirect
  end

  test "update redirects on success" do
    item = create(:config_item, scope: @company)

    patch company_config_item_path(item), params: {
      config_item: { value: "new_val" }
    }
    assert_response :redirect
  end

  test "destroy redirects" do
    item = create(:config_item, scope: @company)

    delete company_config_item_path(item)
    assert_response :redirect
  end
end
