# frozen_string_literal: true

require "test_helper"

# Regression coverage for the soft-delete of users (Sentry PALAD-AI-RAILS-27):
# once an admin soft-deletes a user, that account must no longer be treated as
# authenticated on an existing session. AuthConcern#current_user scopes the
# lookup with `not_deleted`, so a soft-deleted user is dropped and require_auth
# bounces the request to the login page.
class Web::AuthSoftDeletedUserTest < ActionDispatch::IntegrationTest
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
end
