# frozen_string_literal: true

require "test_helper"

# CAP-3: Microsoft work/school accounts. "Sign in with Teams" is this flow —
# Teams federates to Entra, and the exchange is ordinary OIDC.
class Web::MicrosoftSignInTest < ActionDispatch::IntegrationTest
  include OmniAuthHelper

  setup do
    @company = create(:company, :auto_accept, email_domain: "entra-acme.test")
    @microsoft = IdentityProvider.deployment!("microsoft")
  end

  test "a first-time Entra user in a matching domain is signed in and auto-joined" do
    assert_difference "User.count", 1 do
      with_mocked_microsoft_auth(email: "new@entra-acme.test") do
        get MICROSOFT_CALLBACK_PATH
      end
    end

    user = User.find_by(email: "new@entra-acme.test")
    assert_equal @company, user.company_memberships.first.company
    # Identity is keyed on the immutable object id, not the address.
    assert_equal "entra-oid-1", user.user_identities.for_kind("microsoft").first.subject
    assert UserSession.live.exists?(user: user)
  end

  test "a returning user is matched by object id even after their address changes" do
    user = create(:user, company: @company, email: "old@entra-acme.test")
    create(:user_identity, user: user, identity_provider: @microsoft, subject: "entra-oid-1")

    assert_no_difference "User.count" do
      with_mocked_microsoft_auth(email: "renamed@entra-acme.test") do
        get MICROSOFT_CALLBACK_PATH
      end
    end

    assert UserSession.live.exists?(user: user)
  end

  test "a personal Microsoft account cannot take over an existing address" do
    existing = create(:user, company: @company, email: "target@entra-acme.test")

    with_mocked_microsoft_auth(email: existing.email, oid: "attacker-oid",
                               tid: Auth::Methods::Microsoft::PERSONAL_ACCOUNTS_TENANT) do
      get MICROSOFT_CALLBACK_PATH
    end

    # No promotion: a personal account's address is self-asserted, so it never
    # attaches to somebody else's account.
    assert_equal 0, existing.user_identities.for_kind("microsoft").count
    refute UserSession.live.exists?(user: existing)
  end

  test "Microsoft cannot attach itself to an account that already exists" do
    # Entra sends no email_verified claim and does not prove domain ownership —
    # anyone can create a tenant and set a user's address to a victim's. So a
    # Microsoft sign-in may create an account but never adopt one.
    existing = create(:user, company: @company, email: "already-here@entra-acme.test")

    assert_no_difference "User.count" do
      with_mocked_microsoft_auth(email: existing.email, oid: "attacker-oid") do
        get MICROSOFT_CALLBACK_PATH
      end
    end

    assert_redirected_to login_path(error: "link_required")
    assert_equal 0, existing.user_identities.for_kind("microsoft").count
    refute UserSession.live.exists?(user: existing)
  end

  test "a super admin cannot sign in through Microsoft" do
    super_admin = create(:user, :super_admin)

    with_mocked_microsoft_auth(email: super_admin.email) do
      get MICROSOFT_CALLBACK_PATH
    end

    assert_redirected_to login_path(error: "super_admin_password_only")
    refute UserSession.live.exists?(user: super_admin)
  end
end
