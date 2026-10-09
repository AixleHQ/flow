# frozen_string_literal: true

require "test_helper"

# Forgotten passwords: an emailed link, spent by the form it opens.
class Web::PasswordResetsTest < ActionDispatch::IntegrationTest
  NEW_PASSWORD = "ResetPassword4!"

  setup do
    @company = create(:company, email_domain: "resets-acme.test")
    @user = create(:user, :onboarding_completed, company: @company, email: "member@resets-acme.test",
                                                 password: AuthHelper::TEST_PASSWORD)
  end

  def request_reset(email)
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { post password_resets_path, params: { email: email } }
    ActionMailer::Base.deliveries.last
  end

  def token_from(mail)
    CGI.unescape(mail.text_part.decoded[%r{/password/reset/([^\s"]+)}, 1])
  end

  def reset_with(token, password: NEW_PASSWORD, confirmation: password)
    perform_enqueued_jobs do
      patch password_reset_path(token: token), params: { password: password, passwordConfirmation: confirmation }
    end
  end

  test "asking for a link says the same thing whether or not the address has an account" do
    mail = request_reset(@user.email)
    assert_redirected_to new_password_reset_path(sent: "1")
    assert_equal [ @user.email ], mail.to

    assert_nil request_reset("nobody@resets-acme.test")
    assert_redirected_to new_password_reset_path(sent: "1")
  end

  test "opening the link spends nothing; choosing a password does, exactly once" do
    token = token_from(request_reset(@user.email))
    elsewhere = UserSession.start!(user: @user)

    get edit_password_reset_path(token: token)
    assert_inertia_page "Auth/PasswordResetPage"
    assert_inertia_props { |props| props[:valid] == true }

    reset_with(token)

    assert_redirected_to login_path(email: @user.email)
    assert @user.reload.authenticate(NEW_PASSWORD)
    assert elsewhere.reload.revoked_at, "a reset signs out every session the old password let in"
    assert_equal "Your Aixle Flow password was reset", ActionMailer::Base.deliveries.last.subject
    assert_equal "password_reset", Audit.where(auditable: @user).last.action

    get edit_password_reset_path(token: token)
    assert_inertia_props { |props| props[:valid] == false }

    reset_with(token, password: "AnotherOne5!")
    assert_redirected_to edit_password_reset_path(token: token)
    assert @user.reload.authenticate(NEW_PASSWORD), "a spent link must not set a password"
  end

  test "a link expires after an hour" do
    token = token_from(request_reset(@user.email))

    travel 61.minutes do
      reset_with(token)
    end

    assert_redirected_to edit_password_reset_path(token: token)
    assert @user.reload.authenticate(AuthHelper::TEST_PASSWORD)
  end

  test "a refused password keeps the link usable" do
    token = token_from(request_reset(@user.email))

    reset_with(token, password: NEW_PASSWORD, confirmation: "not-the-same")

    assert_redirected_to edit_password_reset_path(token: token)
    assert_equal({ password_confirmation: "The passwords do not match." }, session[:inertia_errors])

    reset_with(token)
    assert @user.reload.authenticate(NEW_PASSWORD)
  end

  test "someone onboarded without a password can choose one through the link" do
    @user.update_columns(password_digest: nil)

    reset_with(token_from(request_reset(@user.email)))

    assert @user.reload.authenticate(NEW_PASSWORD)
    assert @user.user_identities.for_kind("password").exists?
  end

  test "a workspace that takes no passwords is not sent a link" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: IdentityProvider.password).update!(enabled: false)

    assert_nil request_reset(@user.email)
  end

  test "the platform operator's password is not reset by email" do
    operator = create(:user, :super_admin, email: "operator@resets-acme.test", password: AuthHelper::TEST_PASSWORD)

    assert_nil request_reset(operator.email)
  end

  test "from Profile → Security, the link goes to the signed-in address and the session survives the reset" do
    sign_in_as(@user)

    mail = request_reset("someone-else@resets-acme.test")

    assert_redirected_to security_profile_path
    assert_equal [ @user.email ], mail.to

    reset_with(token_from(mail))

    assert_redirected_to security_profile_path
    get security_profile_path
    assert_response :success
  end
end
