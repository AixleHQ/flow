# frozen_string_literal: true

require "test_helper"

# CAP-6: a customer's directory provisions and deprovisions members of THEIR
# company. The bearer token is what scopes the request — there is no tenant in
# the path, so a leaked URL reveals nothing.
class Scim::UsersTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @configuration = ScimConfiguration.create!(company: @company, token_digest: "placeholder-#{SecureRandom.hex(4)}")
    @token = @configuration.regenerate_token!
    @existing = create(:user, company: @company)
  end

  def scim_headers
    { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/scim+json" }
  end

  test "a directory lists only its own company's members" do
    other = create(:user, company: create(:company))

    get "/scim/Users", headers: scim_headers

    assert_response :success
    # Parsed by hand: the response is application/scim+json, which Rails does
    # not register as a JSON type, so parsed_body hands back the raw string.
    emails = JSON.parse(response.body)["Resources"].map { |r| r["userName"] }
    assert_includes emails, @existing.email
    refute_includes emails, other.email
  end

  test "provisioning creates the membership but never an identity" do
    assert_difference "CompanyMembership.count", 1 do
      post "/scim/Users", headers: scim_headers, params: {
        schemas: [ "urn:ietf:params:scim:schemas:core:2.0:User" ],
        userName: "joiner@#{@company.email_domain}",
        name: { givenName: "New", familyName: "Joiner" },
        active: true
      }.to_json
    end

    assert_response :created
    user = User.find_by(email: "joiner@#{@company.email_domain}")
    assert_equal @company, user.company_memberships.first.company
    # AD-10: the first real sign-in creates the identity, not the directory.
    assert_equal 0, user.user_identities.count
  end

  test "deactivating a member revokes the membership through the state machine" do
    membership = @existing.company_memberships.find_by(company: @company)

    patch "/scim/Users/#{membership.id}", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:api:messages:2.0:PatchOp" ],
      Operations: [ { op: "replace", path: "active", value: false } ]
    }.to_json

    assert_response :success
    assert_equal "revoked", membership.reload.state
  end

  test "a directory cannot deactivate the last admin out of a company" do
    # Deprovisioning is meant to be the whole point of directory sync, but a
    # company whose only administrator is switched off has nobody left who can
    # change its policy, invite anyone, or turn the sync off again.
    admin = create(:user, company: @company, membership_role: "admin")
    membership = admin.company_memberships.find_by(company: @company)
    assert_equal 1, @company.company_memberships.active.where(role: "admin").count

    patch "/scim/Users/#{membership.id}", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:api:messages:2.0:PatchOp" ],
      Operations: [ { op: "replace", path: "active", value: false } ]
    }.to_json

    assert_equal "active", membership.reload.state, "the last admin must survive a deprovisioning"
  end

  test "a directory may deactivate an admin while another one remains" do
    first = create(:user, company: @company, membership_role: "admin")
    create(:user, company: @company, membership_role: "admin")
    membership = first.company_memberships.find_by(company: @company)

    patch "/scim/Users/#{membership.id}", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:api:messages:2.0:PatchOp" ],
      Operations: [ { op: "replace", path: "active", value: false } ]
    }.to_json

    assert_response :success
    assert_equal "revoked", membership.reload.state
  end

  test "a rename cannot repoint a membership at somebody else's account" do
    # The critical one: without this guard a directory could PATCH userName to an
    # unrelated address and hand that stranger whatever role the row held —
    # including admin — while detaching the original holder.
    victim = create(:user, company: create(:company))
    membership = @existing.company_memberships.find_by(company: @company)

    patch "/scim/Users/#{membership.id}", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:api:messages:2.0:PatchOp" ],
      Operations: [ { op: "replace", path: "userName", value: victim.email } ]
    }.to_json

    assert_equal @existing, membership.reload.user
    assert_equal victim.email, victim.reload.email
  end

  test "userName is immutable: a directory cannot rename a member at all" do
    # The address is set once, at provisioning. Changing who a membership points
    # at is an account-level act that belongs to the person, not to a directory —
    # so the whole rename path is closed rather than guarded.
    membership = @existing.company_memberships.find_by(company: @company)
    original = @existing.email

    patch "/scim/Users/#{membership.id}", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:api:messages:2.0:PatchOp" ],
      Operations: [ { op: "replace", path: "userName", value: "renamed@#{@company.email_domain}" } ]
    }.to_json

    assert_equal original, @existing.reload.email
    assert_equal @existing, membership.reload.user
  end

  test "a directory cannot conscript an account outside the domain it owns" do
    outsider = create(:user, company: create(:company), email: "outsider@elsewhere.test")

    post "/scim/Users", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:schemas:core:2.0:User" ],
      userName: outsider.email, active: true
    }.to_json

    membership = outsider.company_memberships.find_by(company: @company)
    assert_not_nil membership, "the membership is created, as an invitation"
    # But NOT active: acceptance is the person's, exactly as for a hand-written
    # invitation. The directory only proves it owns its own domain.
    assert_equal "invited", membership.state
  end

  test "a directory can write with no CSRF token, because it is not a browser" do
    # The test environment disables forgery protection, so every other test here
    # would pass against a controller that rejects a real directory's request
    # with "Can't verify CSRF token authenticity" — which is exactly what
    # happened until this was caught against a running app. Turn protection ON
    # for this one test so the guard is real.
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    assert_difference "CompanyMembership.count", 1 do
      post "/scim/Users", headers: scim_headers, params: {
        schemas: [ "urn:ietf:params:scim:schemas:core:2.0:User" ],
        userName: "csrfless@#{@company.email_domain}", active: true
      }.to_json
    end

    assert_response :created
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "an unknown token is refused" do
    get "/scim/Users", headers: { "Authorization" => "Bearer ascim_not-a-real-token" }

    assert_response :unauthorized
  end

  test "a disabled configuration stops working immediately" do
    @configuration.update!(enabled: false)

    get "/scim/Users", headers: scim_headers

    assert_response :unauthorized
  end

  test "using the token records that the directory is alive" do
    get "/scim/Users", headers: scim_headers

    assert_not_nil @configuration.reload.last_seen_at
  end

  # The paths a real provider sends. Entra and Okta take the base URL the UI
  # hands out and append the SCIM-fixed "/Users" — so these are the only
  # spellings that matter, and a test free to pick its own URL never notices
  # when routing answers a different one.
  test "the canonical SCIM paths are the ones that route" do
    assert_routing({ method: "get", path: "/scim/Users" }, { controller: "scim/users", action: "index" })
    assert_routing({ method: "post", path: "/scim/Users" }, { controller: "scim/users", action: "create" })
    assert_routing({ method: "get", path: "/scim/Users/1" },
                   { controller: "scim/users", action: "show", id: "1" })
    assert_routing({ method: "delete", path: "/scim/Users/1" },
                   { controller: "scim/users", action: "destroy", id: "1" })
  end

  # PUT and PATCH are different operations in SCIM: a PUT carries a whole
  # resource, a PATCH carries an "Operations" list. Scimitar splits them across
  # #replace and #update, and `resources` would have pointed both at #update.
  test "PUT replaces and PATCH patches" do
    assert_routing({ method: "put", path: "/scim/Users/1" },
                   { controller: "scim/users", action: "replace", id: "1" })
    assert_routing({ method: "patch", path: "/scim/Users/1" },
                   { controller: "scim/users", action: "update", id: "1" })
  end

  test "a created member is located at a URL the provider can fetch" do
    post "/scim/Users", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:schemas:core:2.0:User" ],
      userName: "located@#{@company.email_domain}", active: true
    }.to_json

    assert_response :created
    location = JSON.parse(response.body).dig("meta", "location")
    assert_match %r{/scim/Users/\d+\z}, location

    get URI.parse(location).path, headers: scim_headers

    assert_response :success
  end
end
