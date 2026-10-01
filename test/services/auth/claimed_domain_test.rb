# frozen_string_literal: true

require "test_helper"

class Auth::ClaimedDomainTest < ActiveSupport::TestCase
  setup do
    @company = create(:company, :auto_accept, name: "Claimed Acme", email_domain: "claimed-acme.test")
    @google = IdentityProvider.deployment!("google")
    @microsoft = IdentityProvider.deployment!("microsoft")
  end

  def outsider = create(:user, email: "outsider@claimed-acme.test")

  def disable!(provider)
    CompanyAuthPolicy.find_by!(company: @company, identity_provider: provider).update!(enabled: false)
  end

  test "names the workspace and the sign-ins that would add someone to it" do
    disable!(@microsoft)

    assert_equal(
      { domain: "claimed-acme.test", workspace_name: "Claimed Acme", join_methods: [ "Google" ],
        approval_required: false },
      Auth::ClaimedDomain.for(outsider).to_h
    )
  end

  # A password, a passkey and an emailed link are all accepted here, and none of
  # them adds anybody: offering one would send the person straight back.
  test "never offers a method that only admits existing members" do
    disable!(@google)
    disable!(@microsoft)

    assert_empty Auth::ClaimedDomain.for(outsider).to_h[:join_methods]
  end

  test "names the workspace's own connection" do
    resolve_hosts_publicly!
    connection = create(:identity_provider, company: @company, kind: "oidc", name: "Acme Okta",
                                            config: { "issuer" => "https://okta.claimed-acme.test", "client_id" => "c" })
    create(:company_auth_policy, company: @company, identity_provider: connection, enabled: true)

    assert_equal [ "Google", "Microsoft", "Acme Okta" ], Auth::ClaimedDomain.for(outsider).to_h[:join_methods]
  end

  # Whatever kept them out through it — an address it did not prove — keeps them
  # out the next time too.
  test "does not send someone back to the method that just failed to add them" do
    assert_equal [ "Google" ], Auth::ClaimedDomain.for(outsider, tried: @microsoft).to_h[:join_methods]
  end

  test "says when joining waits for an administrator" do
    @company.update!(auto_accept_users: false)

    assert Auth::ClaimedDomain.for(outsider).to_h[:approval_required]
  end

  # An unproved claim may be somebody else's domain, and auto-join does not run
  # for it, so an invitation is the only way in.
  test "an unproved domain is neither named nor offered a way in" do
    @company.update!(domain_verified_at: nil)

    claim = Auth::ClaimedDomain.for(outsider).to_h

    assert_equal "claimed-acme.test", claim[:domain]
    assert_nil claim[:workspace_name]
    assert_empty claim[:join_methods]
  end

  test "nobody who belongs somewhere, a super admin, or an unclaimed domain" do
    member = create(:user, email: "member@claimed-acme.test")
    create(:company_membership, user: member, company: create(:company), state: "invited")

    assert_nil Auth::ClaimedDomain.for(member)
    assert_nil Auth::ClaimedDomain.for(create(:user, :super_admin, email: "operator@claimed-acme.test"))
    assert_nil Auth::ClaimedDomain.for(create(:user, email: "someone@unclaimed-#{SecureRandom.hex(3)}.test"))
  end
end
