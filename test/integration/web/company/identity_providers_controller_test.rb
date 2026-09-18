# frozen_string_literal: true

require "test_helper"

# A company connecting its own OpenID Connect provider (CAP-3). A new connection
# arrives DISABLED: AD-7 requires it be proved by a real sign-in before it can be
# switched on, which is what stops a misconfigured connection locking a workspace
# out.
class Web::Company::IdentityProvidersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                           password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    @member = create(:user, :onboarding_completed, company: @company,
                            password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
  end

  def connection_params
    { name: "Acme SSO", issuer: "https://idp.acme.test", client_id: "acme-client",
      client_secret: "acme-secret" }
  end

  test "an admin can connect an identity provider, and it arrives switched off" do
    sign_in_as(@admin)

    assert_difference "IdentityProvider.count", 1 do
      post company_identity_providers_path, params: connection_params
    end

    provider = @company.identity_providers.order(:id).last
    assert_equal "oidc", provider.kind
    assert_equal "https://idp.acme.test", provider.issuer
    assert_equal "acme-secret", provider.client_secret
    # Never a plaintext column.
    refute_equal "acme-secret", provider.encrypted_secret
    refute CompanyAuthPolicy.find_by!(company: @company, identity_provider: provider).enabled
  end

  test "the client secret is never serialized back to the browser" do
    sign_in_as(@admin)
    post company_identity_providers_path, params: connection_params

    get company_auth_policies_path

    assert_response :success
    refute_match "acme-secret", response.body
  end

  test "a non-admin member cannot connect one" do
    sign_in_as(@member)

    assert_no_difference "IdentityProvider.count" do
      post company_identity_providers_path, params: connection_params
    end
  end

  test "an update with a blank secret leaves the stored one alone" do
    sign_in_as(@admin)
    post company_identity_providers_path, params: connection_params
    provider = @company.identity_providers.order(:id).last

    patch company_identity_provider_path(provider), params: { name: "Renamed", client_secret: "" }

    assert_equal "Renamed", provider.reload.name
    assert_equal "acme-secret", provider.client_secret
  end

  test "removing a connection somebody depends on is refused, exactly as disabling it would be" do
    connection = create(:identity_provider, company: @company, kind: "oidc", name: "Acme SSO")
    create(:company_auth_policy, company: @company, identity_provider: connection, enabled: true)
    # This member holds ONLY the connection: no password, so removing it leaves
    # them with nothing.
    sso_only = create(:user, :onboarding_completed, company: @company, password: nil, password_confirmation: nil)
    create(:user_identity, user: sso_only, identity_provider: connection, subject: "sso-only-sub")
    sign_in_as(@admin)

    delete company_identity_provider_path(connection)

    assert IdentityProvider.exists?(connection.id), "the connection must survive a refused removal"
    assert CompanyAuthPolicy.exists?(company: @company, identity_provider: connection)
  end

  test "removing a connection nobody depends on succeeds" do
    connection = create(:identity_provider, company: @company, kind: "oidc", name: "Unused SSO")
    create(:company_auth_policy, company: @company, identity_provider: connection, enabled: false)
    sign_in_as(@admin)

    delete company_identity_provider_path(connection)

    refute IdentityProvider.exists?(connection.id)
  end

  test "another company's connection is not reachable" do
    other = create(:company)
    foreign = create(:identity_provider, company: other, kind: "oidc")
    sign_in_as(@admin)

    delete company_identity_provider_path(foreign)

    assert_response :not_found
    assert IdentityProvider.exists?(foreign.id)
  end
end
