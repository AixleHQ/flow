# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for Profile → Security → Sign-in methods,
# via the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# There is no Pundit policy: these are the person's own credentials (AD-18), so
# every role may manage its own and nobody may reach anyone else's. The gate is
# the scope — identities are looked up through current_user — which makes
# another person's identity a 404 rather than a refusal that would confirm it
# exists.
class Web::SignInMethodsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  EVERYONE_FOR_THEMSELVES = AuthorizationMatrix::ROLES.index_with { :allowed_write }.freeze
  NOBODY = AuthorizationMatrix::ROLES.index_with { :not_found }.freeze

  setup do
    setup_company_authz_personas
    google = IdentityProvider.deployment!("google")
    @identities = AuthorizationMatrix::ROLES.index_with do |role|
      create(:user_identity, user: user_for(role), identity_provider: google)
    end
    @somebody_elses = create(:user_identity, user: create_member(:employee), identity_provider: google)
  end

  teardown { teardown_authz }

  test "create starts a link for every role, for their own account" do
    assert_role_matrix(EVERYONE_FOR_THEMSELVES, transport: :web, allowed_status: :temporary_redirect) do
      post sign_in_methods_path, params: { kind: "google" }
    end
  end

  test "destroy removes a role's own linked method" do
    assert_role_matrix(EVERYONE_FOR_THEMSELVES, transport: :web) do |role|
      delete sign_in_method_path(@identities.fetch(role))
    end
    assert_empty UserIdentity.where(id: @identities.values.map(&:id))
  end

  test "destroy cannot reach somebody else's method" do
    assert_role_matrix(NOBODY, transport: :web) { delete sign_in_method_path(@somebody_elses) }
    assert UserIdentity.exists?(@somebody_elses.id)
  end

  test "anonymous requests are sent to sign in" do
    post sign_in_methods_path, params: { kind: "google" }
    assert_redirected_to login_path

    delete sign_in_method_path(@somebody_elses)
    assert_redirected_to login_path
    assert UserIdentity.exists?(@somebody_elses.id)
  end

  test "a super admin is sent to the admin panel and links nothing" do
    sign_in_as(create(:user, :super_admin, password: AuthHelper::TEST_PASSWORD))

    post sign_in_methods_path, params: { kind: "google" }

    assert_redirected_to admin_root_path
  end
end
