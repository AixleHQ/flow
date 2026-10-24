# frozen_string_literal: true

require "test_helper"

class Admin::NavigationTest < ActionDispatch::IntegrationTest
  setup do
    @operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@operator)
  end

  test "every admin page offers a sign-out that leaves Turbo out of it" do
    get admin_companies_path

    assert_response :success
    assert_select "nav.navigation form.navigation__sign-out[action=?][data-turbo=false]", logout_path do
      assert_select "input[name=_method][value=delete]", 1
      assert_select "button", text: "Sign out"
    end
  end

  test "back to the app is offered only during an impersonation" do
    get admin_companies_path
    assert_select "nav.navigation a[href=?]", root_url, count: 0

    member = create(:user, :admin, :onboarding_completed)
    post impersonate_admin_user_path(member)
    get admin_companies_path

    assert_select "nav.navigation a[href=?]", root_url, count: 1
  end
end
