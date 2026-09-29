# frozen_string_literal: true

require "test_helper"

# A sign-in is a UserSession row: the server can end it, and it ends by itself
# after the idle timeout or at its maximum age.
class Web::UserSessionsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  test "signing in starts a session the server can end" do
    sign_in_as(@user)
    assert_equal @user, UserSession.sole.user
    get profile_path
    assert_response :success

    UserSession.revoke_all_for!(@user)

    get profile_path
    assert_redirected_to login_path
  end

  test "signing out ends the session" do
    sign_in_as(@user)

    delete logout_path

    assert UserSession.sole.revoked_at
  end

  test "a session left unused past the idle timeout is over" do
    sign_in_as(@user)

    travel(UserSession.idle_timeout + 1.minute) do
      get profile_path
      assert_redirected_to login_path
    end
  end

  test "a session is over at its maximum age, however much it is used" do
    sign_in_as(@user)
    UserSession.sole.update_columns(created_at: (UserSession.max_age + 1.minute).ago)

    get profile_path

    assert_redirected_to login_path
  end

  test "signing out everywhere else ends the other browsers and keeps this one" do
    elsewhere = UserSession.start!(user: @user)
    sign_in_as(@user)

    delete sign_out_other_sessions_profile_path

    assert elsewhere.reload.revoked_at
    get profile_path
    assert_response :success
  end

  test "suspending the account ends its sessions" do
    sign_in_as(@user)

    @user.suspend!

    assert UserSession.sole.revoked_at
    get profile_path
    assert_redirected_to login_path
  end

  test "a new password ends the sessions signed in with the old one" do
    sign_in_as(@user)

    @user.update!(password: "AnotherPassword2!")

    assert UserSession.sole.revoked_at
  end

  test "each sign-in gets a fresh session" do
    sign_in_as(@user)
    first = UserSession.sole

    sign_in_as(@user)

    assert first.reload.revoked_at
    assert_equal 1, UserSession.live.where(user: @user).count
  end
end
