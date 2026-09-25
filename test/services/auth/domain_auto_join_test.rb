# frozen_string_literal: true

require "test_helper"

# Email-domain auto-join (AD-4, AD-7).
#
# The domain decides WHICH company, but the method decides WHETHER: a company
# that does not accept the provider someone signed in with must not gain a
# member through it.
class Auth::DomainAutoJoinTest < ActiveSupport::TestCase
  setup do
    @company = create(:company, :auto_accept, email_domain: "autojoin-acme.test")
    @google = IdentityProvider.deployment!("google")
    @password = IdentityProvider.password
  end

  def newcomer
    create(:user, email: "newcomer@autojoin-acme.test")
  end

  def disable!(provider)
    CompanyAuthPolicy.find_or_create_by!(company: @company, identity_provider: provider)
                     .update!(enabled: false)
  end

  test "a company that accepts the method gains the member" do
    user = newcomer

    assert_difference "CompanyMembership.count", 1 do
      Auth::DomainAutoJoin.call(user, provider: @google)
    end

    assert_equal @company, user.company_memberships.sole.company
  end

  test "a company that has switched that method off gains nobody" do
    disable!(@google)
    user = newcomer

    assert_no_difference "CompanyMembership.count" do
      Auth::DomainAutoJoin.call(user, provider: @google)
    end
  end

  test "an unusable membership would freeze the policy screen, so it is never created" do
    # Driven through the resolver rather than the factory on purpose: someone who
    # arrives by Google has NO password, so their only identity is the Google
    # one. A factory-built user carries a password identity and would never be
    # stranded, which would make this test prove nothing.
    admin = create(:user, email: "admin@autojoin-acme.test",
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    create(:company_membership, user: admin, company: @company, role: "admin", state: "active")
    disable!(@google)

    assertion = Auth::Assertion.new(
      provider: @google, subject: "google-subject-1",
      email: "newcomer@autojoin-acme.test", email_verified: true, name: "Newcomer"
    )
    arrival = Auth::IdentityResolver.new(assertion).resolve

    # The account exists and holds its Google identity — only the membership is
    # withheld, because this company cannot admit that method.
    assert_equal [ @google.id ], arrival.user_identities.map(&:identity_provider_id)
    assert_empty arrival.company_memberships

    # Nobody is stranded, so an edit touching neither them nor Google still goes
    # through. With the membership created, this would be refused for their sake
    # and the policy screen would stay refused for good.
    magic_link = IdentityProvider.deployment!("magic_link")
    prospective = Auth::PolicyResolver.allowed_provider_ids(@company) - [ magic_link.id ]

    assert_empty Auth::PolicyResolver.stranded_members(@company, prospective)
    assert Auth::PolicyUpdater.new(company: @company, actor: admin).set(magic_link, enabled: false),
      "an unusable membership would have frozen this company's policy screen"
  end

  test "auto-join still yields to any membership the person already has" do
    user = newcomer
    other = create(:company, email_domain: "somewhere-else.test")
    create(:company_membership, user: user, company: other, state: "invited")

    assert_no_difference "CompanyMembership.count" do
      Auth::DomainAutoJoin.call(user, provider: @google)
    end
  end

  test "a domain no company claims joins nothing" do
    user = create(:user, email: "someone@unclaimed-#{SecureRandom.hex(3)}.test")

    assert_no_difference "CompanyMembership.count" do
      Auth::DomainAutoJoin.call(user, provider: @google)
    end
  end

  test "a super_admin is never auto-joined" do
    user = create(:user, :super_admin, email: "operator@autojoin-acme.test")

    assert_no_difference "CompanyMembership.count" do
      Auth::DomainAutoJoin.call(user, provider: @google)
    end
  end

  test "another company's connection never carries someone into this one" do
    # A company-scoped connection is only ever in its OWN company's allowed set,
    # so it cannot be the method that admits someone to a company that never
    # agreed to it.
    other = create(:company, email_domain: "other-tenant.test")
    connection = create(:identity_provider, company: other, kind: "oidc", name: "Other SSO",
                                            config: { "issuer" => "https://other.test", "client_id" => "c" })
    create(:company_auth_policy, company: other, identity_provider: connection, enabled: true)

    assert_no_difference "CompanyMembership.count" do
      Auth::DomainAutoJoin.call(newcomer, provider: connection)
    end
  end
end
