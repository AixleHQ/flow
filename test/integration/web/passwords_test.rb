# frozen_string_literal: true

require "test_helper"

# Profile → Security → Password: a first password for someone onboarded without
# one, and a change for someone who has one.
class Web::PasswordsTest < ActionDispatch::IntegrationTest
  include OmniAuthHelper

  NEW_PASSWORD = "BrandNewPassword3!"

  setup do
    @company = create(:company, email_domain: "passwords-acme.test")
    @google = IdentityProvider.deployment!("google")
  end

  def google_only_user
    user = create(:user, :admin, :onboarding_completed, company: @company, email: "admin@passwords-acme.test",
                                                         password: nil, password_confirmation: nil)
    create(:user_identity, user: user, identity_provider: @google, subject: "g-admin", email: user.email)
    user
  end

  def sign_in_with_google(user)
    with_mocked_google_auth(email: user.email, uid: "g-admin") { get GOOGLE_CALLBACK_PATH }
  end

  test "an admin onboarded without a password sets one and can then sign in with it" do
    user = google_only_user
    sign_in_with_google(user)

    get security_profile_path
    assert_inertia_props do |props|
      props[:password][:set] == false && props[:password][:changedAt].nil? && props[:password][:accepted] == true &&
        props[:signInMethods].sole[:removalRefusal] == "Google is your only way to sign in."
    end

    perform_enqueued_jobs do
      patch profile_password_path, params: { password: NEW_PASSWORD, passwordConfirmation: NEW_PASSWORD }
    end

    assert_redirected_to security_profile_path
    assert_match(/Password set/, flash[:notice])
    assert user.reload.authenticate(NEW_PASSWORD)
    assert_equal "A password was set on your Aixle Flow account", ActionMailer::Base.deliveries.last.subject
    assert_equal "password_set", Audit.where(auditable: user).last.action

    get security_profile_path
    assert_response :success, "the session that set the password stays signed in"
    assert_inertia_props do |props|
      methods = props[:signInMethods].index_by { |method| method[:kind] }
      props[:password][:set] == true && props[:password][:changedAt].present? &&
        methods.key?("password") && methods["google"][:removalRefusal].nil?
    end

    delete logout_path
    sign_in_as(user, password: NEW_PASSWORD)
    assert UserSession.live.exists?(user: user)
  end

  test "changing a password needs the current one, and says what is wrong inline" do
    user = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(user)

    patch profile_password_path, params: { password: NEW_PASSWORD, passwordConfirmation: NEW_PASSWORD }
    assert_equal({ current_password: "Enter your current password." }, session[:inertia_errors])

    patch profile_password_path, params: { currentPassword: "not-it", password: NEW_PASSWORD, passwordConfirmation: NEW_PASSWORD }
    assert_equal({ current_password: "That is not your current password." }, session[:inertia_errors])

    patch profile_password_path, params: { currentPassword: AuthHelper::TEST_PASSWORD, password: "short", passwordConfirmation: "short" }
    assert_equal({ password: "Use at least 8 characters." }, session[:inertia_errors])

    patch profile_password_path, params: { currentPassword: AuthHelper::TEST_PASSWORD, password: NEW_PASSWORD, passwordConfirmation: "different1" }
    assert_equal({ password_confirmation: "The passwords do not match." }, session[:inertia_errors])

    assert user.reload.authenticate(AuthHelper::TEST_PASSWORD), "nothing refused may change the password"
    assert_empty Audit.where(auditable: user)
  end

  test "a change signs out every other session and keeps this one" do
    user = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    elsewhere = UserSession.start!(user: user)
    sign_in_as(user)

    perform_enqueued_jobs do
      patch profile_password_path, params: { currentPassword: AuthHelper::TEST_PASSWORD, password: NEW_PASSWORD,
                                             passwordConfirmation: NEW_PASSWORD }
    end

    assert_redirected_to security_profile_path
    assert elsewhere.reload.revoked_at
    assert_equal 1, UserSession.live.where(user: user).count
    assert_equal "Your Aixle Flow password was changed", ActionMailer::Base.deliveries.last.subject
    assert_equal "password_changed", Audit.where(auditable: user).last.action

    get security_profile_path
    assert_inertia_props { |props| props[:sessions].sole[:current] == true }
  end

  test "a workspace that takes no passwords is not offered one" do
    user = google_only_user
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: IdentityProvider.password).update!(enabled: false)
    sign_in_with_google(user)

    get security_profile_path
    assert_inertia_props { |props| props[:password][:accepted] == false }

    patch profile_password_path, params: { password: NEW_PASSWORD, passwordConfirmation: NEW_PASSWORD }

    assert_redirected_to security_profile_path
    assert_match(/accepts a password/, flash[:alert])
    assert_not user.reload.password_set?
  end

  test "an operator impersonating someone cannot set their password" do
    user = google_only_user
    sign_in_as(create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD))
    post impersonate_admin_user_path(user)

    patch profile_password_path, params: { password: NEW_PASSWORD, passwordConfirmation: NEW_PASSWORD }

    assert_redirected_to security_profile_path
    assert_match(/while impersonating/, flash[:alert])
    assert_not user.reload.password_set?
  end

  test "setting a password needs a session" do
    patch profile_password_path, params: { password: NEW_PASSWORD, passwordConfirmation: NEW_PASSWORD }

    assert_redirected_to login_path
  end
end
