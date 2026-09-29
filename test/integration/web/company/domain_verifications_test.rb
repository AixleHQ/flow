# frozen_string_literal: true

require "test_helper"

# Proving the domain is what turns domain auto-join on, so it is a write on the
# Access tab rather than a question the page answers by itself.
class Web::Company::DomainVerificationsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, :domain_unverified, email_domain: "acme-robotics.example")
    @admin = create(:user, :onboarding_completed, company: @company, membership_role: "admin",
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@admin)
  end

  def host = "_aixle-challenge.acme-robotics.example"

  def record = Domains::Verification.record_for(@company)

  test "the screen carries what to publish and where" do
    get company_settings_access_path

    assert_inertia_props do |props|
      assert_equal host, props[:joining][:verificationHost]
      assert_match(/\Aaixle-domain-verification=/, props[:joining][:verificationRecord])
      assert_nil props[:joining][:domainVerifiedAt]
      true
    end
  end

  test "a published record verifies the domain" do
    published_txt_records(host => [ record ])

    post company_domain_verification_path

    assert_redirected_to company_settings_access_path
    assert @company.reload.domain_verified?
  end

  # DNS takes minutes to publish, so the answer has to be "not yet" rather than
  # "no" — and it must say where it looked.
  test "a missing record says so and changes nothing" do
    published_txt_records

    post company_domain_verification_path

    assert_not @company.reload.domain_verified?
    follow_redirect!
    assert_inertia_props { |props| assert_match(/could not find that record at #{host}/, props[:errors][:base]) }
  end

  test "only an administrator may verify it" do
    member = create(:user, :onboarding_completed, company: @company, membership_role: "employee",
                    password: AuthHelper::TEST_PASSWORD)
    sign_in_as(member)
    published_txt_records(host => [ record ])

    post company_domain_verification_path

    assert_not @company.reload.domain_verified?
  end

  # The point of the whole thing: until it is proved, people get in by
  # invitation and not by turning up with the right address.
  test "verifying is what lets a stranger from the domain join" do
    @company.update!(auto_accept_users: true)
    newcomer = create(:user, email: "newcomer@acme-robotics.example")
    google = IdentityProvider.deployment!("google")

    assert_nil Auth::DomainAutoJoin.call(newcomer, provider: google)

    published_txt_records(host => [ record ])
    post company_domain_verification_path

    assert_difference "CompanyMembership.count", 1 do
      Auth::DomainAutoJoin.call(newcomer, provider: google)
    end
  end
end
