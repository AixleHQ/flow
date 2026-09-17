# frozen_string_literal: true

require "test_helper"

# The company-facing surface for AD-4/AD-7: an admin decides which sign-in
# methods this company accepts, and the guard refuses an edit that would strand
# somebody rather than writing it and apologising later.
class Web::Company::AuthPoliciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @password = IdentityProvider.password
    @google = IdentityProvider.deployment!("google")

    @admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                           password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)

    @member = create(:user, :onboarding_completed, company: @company,
                            password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
  end

  test "a member can see which methods the company accepts" do
    sign_in_as(@member)

    get company_auth_policies_path

    assert_response :success
    assert_match "Google", response.body
  end

  test "an admin can turn a method off" do
    sign_in_as(@admin)

    put company_auth_policy_path(@google), params: { enabled: false }

    assert_redirected_to company_auth_policies_path
    refute CompanyAuthPolicy.find_by(company: @company, identity_provider: @google).enabled
  end

  test "a non-admin member cannot change anything" do
    sign_in_as(@member)

    put company_auth_policy_path(@google), params: { enabled: false }

    assert CompanyAuthPolicy.find_by(company: @company, identity_provider: @google).enabled
  end

  test "an edit that would strand members is refused and names them" do
    sign_in_as(@admin)

    put company_auth_policy_path(@password), params: { enabled: false }

    assert_redirected_to company_auth_policies_path
    # Nothing written, and the refusal carries who would have been locked out.
    assert CompanyAuthPolicy.find_by(company: @company, identity_provider: @password).enabled
    follow_redirect!
    assert_match @admin.email, response.body
  end

  test "another company's connection is not reachable from here" do
    other = create(:company)
    foreign = create(:identity_provider, company: other, kind: "oidc")
    sign_in_as(@admin)

    put company_auth_policy_path(foreign), params: { enabled: true }

    # Scoped lookup, so a guessed id is a 404 rather than a cross-tenant write.
    assert_response :not_found
    refute CompanyAuthPolicy.exists?(company: @company, identity_provider: foreign)
  end
end
