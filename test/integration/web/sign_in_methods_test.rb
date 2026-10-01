# frozen_string_literal: true

require "test_helper"

# Profile → Security → Sign-in methods: linking Google or Microsoft from inside
# a session, and removing a linked method. This is where a refused sign-in
# (`link_required`) sends people, so it has to work for exactly the case that
# refusal exists for — a Microsoft account whose address matches an account it
# may not adopt.
class Web::SignInMethodsTest < ActionDispatch::IntegrationTest
  include OmniAuthHelper

  setup do
    @company = create(:company, :auto_accept, email_domain: "linking-acme.test")
    @user = create(:user, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @microsoft = IdentityProvider.deployment!("microsoft")
    @google = IdentityProvider.deployment!("google")
  end

  test "the security page lists the methods held and offers the ones that can be linked" do
    create(:user_identity, user: @user, identity_provider: @google, subject: "g-1", email: "me@gmail.example")
    sign_in_as(@user)

    get security_profile_path

    assert_inertia_page "Profile/Security"
    assert_inertia_props do |props|
      methods = props[:signInMethods].index_by { |method| method[:kind] }
      props[:linkableKinds] == %w[google microsoft] &&
        methods["password"][:removable] == false &&
        methods["google"][:removable] == true &&
        methods["google"][:email] == "me@gmail.example" &&
        methods["google"][:removalRefusal].nil?
    end
  end

  test "a signed-in person links the Microsoft account their address could not adopt" do
    sign_in_as(@user)

    post sign_in_methods_path, params: { kind: "microsoft" }
    assert_response :temporary_redirect
    assert_redirected_to "/auth/microsoft"

    assert_no_difference [ "User.count", "CompanyMembership.count" ] do
      with_mocked_microsoft_auth(email: @user.email, oid: "oid-linked") do
        get MICROSOFT_CALLBACK_PATH
      end
    end

    assert_redirected_to security_profile_path
    assert_match(/Microsoft is linked/, flash[:notice])
    identity = @user.user_identities.for_kind("microsoft").sole
    assert_equal "oid-linked", identity.subject
    assert UserSessionProof.joins(:user_session).exists?(identity_provider: @microsoft,
                                                         user_sessions: { user_id: @user.id, revoked_at: nil })

    # And from now on it is a way in: the same assertion signs this account in.
    delete logout_path
    with_mocked_microsoft_auth(email: @user.email, oid: "oid-linked") do
      get MICROSOFT_CALLBACK_PATH
    end
    refute_equal login_path(error: "link_required"), response.location
    assert UserSession.live.exists?(user: @user)
  end

  test "a Microsoft account that already belongs to someone else is refused, not moved" do
    owner = create(:user, :onboarding_completed, company: @company)
    create(:user_identity, user: owner, identity_provider: @microsoft, subject: "oid-taken")
    sign_in_as(@user)

    post sign_in_methods_path, params: { kind: "microsoft" }
    with_mocked_microsoft_auth(email: @user.email, oid: "oid-taken") do
      get MICROSOFT_CALLBACK_PATH
    end

    assert_redirected_to security_profile_path
    assert_match(/already belongs to a different account/, flash[:alert])
    assert_equal owner, UserIdentity.find_by(identity_provider: @microsoft, subject: "oid-taken").user
    assert_empty @user.user_identities.for_kind("microsoft")
  end

  test "a link whose session ended before the callback attaches nothing and signs nobody in" do
    sign_in_as(@user)
    post sign_in_methods_path, params: { kind: "microsoft" }

    # Signed out everywhere while the person was away at Microsoft.
    UserSession.revoke_all_for!(@user)

    # An address that, as an ordinary sign-in, would CREATE an account in an
    # auto-accept workspace — which is exactly why the callback must not fall
    # through to one.
    assert_no_difference [ "User.count", "UserIdentity.count", "UserSession.count" ] do
      with_mocked_microsoft_auth(email: "brand-new@linking-acme.test", upn: "brand-new@linking-acme.test",
                                 oid: "oid-orphan") do
        get MICROSOFT_CALLBACK_PATH
      end
    end

    assert_redirected_to login_path(error: "link_expired")
    refute UserSession.live.exists?(user: @user)
  end

  test "linking cannot be started without a session" do
    post sign_in_methods_path, params: { kind: "microsoft" }

    assert_redirected_to login_path

    # Nothing was recorded, so the callback is an ordinary sign-in, and an
    # ordinary Microsoft sign-in still never adopts an existing account.
    with_mocked_microsoft_auth(email: @user.email, oid: "oid-anonymous") do
      get MICROSOFT_CALLBACK_PATH
    end

    assert_redirected_to login_path(error: "link_required")
    assert_empty @user.user_identities.for_kind("microsoft")
  end

  test "a method the person's company does not accept cannot be linked" do
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: @microsoft).update!(enabled: false)
    sign_in_as(@user)

    post sign_in_methods_path, params: { kind: "microsoft" }

    assert_redirected_to security_profile_path
    assert_match(/cannot be linked/, flash[:alert])
    with_mocked_microsoft_auth(email: @user.email, oid: "oid-unaccepted") do
      get MICROSOFT_CALLBACK_PATH
    end
    assert_empty @user.user_identities.for_kind("microsoft")
  end

  test "cancelling at the provider returns to the security page with nothing added" do
    sign_in_as(@user)
    post sign_in_methods_path, params: { kind: "google" }

    get auth_failure_path(message: "access_denied")

    assert_redirected_to security_profile_path
    assert_match(/did not finish/, flash[:alert])
    assert_empty @user.user_identities.for_kind("google")
  end

  test "removing a linked method leaves the others" do
    identity = create(:user_identity, user: @user, identity_provider: @google, subject: "g-remove")
    sign_in_as(@user)

    delete sign_in_method_path(identity)

    assert_redirected_to security_profile_path
    assert_match(/Google removed/, flash[:notice])
    assert_not UserIdentity.exists?(identity.id)
    assert @user.user_identities.for_kind("password").exists?
  end

  test "removing the only method the company accepts is refused, with the reason" do
    identity = create(:user_identity, user: @user, identity_provider: @google, subject: "g-only")
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: IdentityProvider.password).update!(enabled: false)
    # A password proof would not get past this company's entry gate any more.
    with_mocked_google_auth(email: @user.email, uid: "g-only") { get GOOGLE_CALLBACK_PATH }

    delete sign_in_method_path(identity)

    assert_redirected_to security_profile_path
    assert_match(/only sign-in method that #{@company.branded_name} accepts/, flash[:alert])
    assert UserIdentity.exists?(identity.id)
  end

  test "an operator impersonating someone cannot change how they sign in" do
    operator = create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD)
    identity = create(:user_identity, user: @user, identity_provider: @google, subject: "g-impersonated")
    sign_in_as(operator)
    post impersonate_admin_user_path(@user)

    post sign_in_methods_path, params: { kind: "microsoft" }
    assert_redirected_to security_profile_path
    with_mocked_microsoft_auth(email: @user.email, oid: "oid-operator") do
      get MICROSOFT_CALLBACK_PATH
    end

    delete sign_in_method_path(identity)

    assert_redirected_to security_profile_path
    assert_match(/while impersonating/, flash[:alert])
    assert_empty @user.user_identities.for_kind("microsoft")
    assert UserIdentity.exists?(identity.id)
  end
end
