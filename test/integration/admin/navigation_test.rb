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

  test "back to the app is offered only during an impersonation, and leaves Turbo out of it" do
    get admin_companies_path
    assert_select "nav.navigation a[href=?]", company_projects_url, count: 0

    member = create(:user, :admin, :onboarding_completed)
    post impersonate_admin_user_path(member)
    get admin_companies_path

    assert_select "nav.navigation a[href=?][data-turbo=false]", company_projects_url, count: 1
  end

  # The landing page at / is full of inline handlers; a Turbo visit there parsed it under the
  # admin page's CSP and every impersonation raised script-src-attr violations.
  test "impersonating opens the app, not the landing page, outside Turbo" do
    member = create(:user, :admin, :onboarding_completed)

    get admin_users_path
    assert_select "form[action=?][data-turbo=false]", impersonate_admin_user_path(member), count: 1

    post impersonate_admin_user_path(member)
    assert_redirected_to company_projects_path
  end
end
