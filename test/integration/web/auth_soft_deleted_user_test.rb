# frozen_string_literal: true

require "test_helper"

# Regression coverage for the soft-delete of users (Sentry PALAD-AI-RAILS-27):
# once an admin soft-deletes a user, that account must no longer be treated as
# authenticated on an existing session. AuthConcern#current_user scopes the
# lookup with `not_deleted`, so a soft-deleted user is dropped and require_auth
# bounces the request to the login page.
class Web::AuthSoftDeletedUserTest < ActionDispatch::IntegrationTest
  include OmniAuthHelper

  setup do
    @user = create(:user, :with_company, :onboarding_completed,
                   password: AuthHelper::TEST_PASSWORD,
                   password_confirmation: AuthHelper::TEST_PASSWORD)
  end

  test "signed-in active user stays authenticated" do
    sign_in_as(@user)

    # A completed-onboarding user hitting /onboarding is bounced onward (into the
    # app), NOT back to the login page — i.e. they are authenticated.
    get onboarding_path

    assert_response :redirect
    assert_not_equal login_path, URI(response.location).path
  end

  test "soft-deleted user is no longer authenticated and is redirected to login" do
    sign_in_as(@user)
    @user.soft_delete!

    get onboarding_path

    assert_redirected_to login_path
  end
  # A soft-deleted account must be refused AT LOGIN, not signed in and then
  # dropped by current_user's `not_deleted` scope (which produced a redirect
  # loop with no explanation).

  test "soft-deleted user cannot sign in with a password" do
    @user.soft_delete!

    post login_path, params: { user: { email: @user.email, password: AuthHelper::TEST_PASSWORD } }

    assert_redirected_to login_path
    get onboarding_path
    assert_redirected_to login_path
  end

  test "soft-deleted user is refused on the Google OAuth path with account_deleted" do
    @user.soft_delete!

    with_mocked_google_auth(email: @user.email) do
      post "/auth/google"
      follow_redirect!
    end

    assert_redirected_to login_path(error: "account_deleted")
  end

  test "soft-deleted member is not listed on the members page" do
    admin = create(:user, :admin, :onboarding_completed,
                   company: @user.companies.first, password: AuthHelper::TEST_PASSWORD)
    @user.soft_delete!
    sign_in_as(admin)

    get company_members_path

    emails = inertia.props[:users].map { |u| u[:email] }
    assert_not_includes emails, @user.email
    assert_includes emails, admin.email
  end
end
