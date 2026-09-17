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

    get "/scim/users", headers: scim_headers

    assert_response :success
    # Parsed by hand: the response is application/scim+json, which Rails does
    # not register as a JSON type, so parsed_body hands back the raw string.
    emails = JSON.parse(response.body)["Resources"].map { |r| r["userName"] }
    assert_includes emails, @existing.email
    refute_includes emails, other.email
  end

  test "provisioning creates the membership but never an identity" do
    assert_difference "CompanyMembership.count", 1 do
      post "/scim/users", headers: scim_headers, params: {
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

    patch "/scim/users/#{membership.id}", headers: scim_headers, params: {
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

    patch "/scim/users/#{membership.id}", headers: scim_headers, params: {
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

    patch "/scim/users/#{membership.id}", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:api:messages:2.0:PatchOp" ],
      Operations: [ { op: "replace", path: "userName", value: "renamed@#{@company.email_domain}" } ]
    }.to_json

    assert_equal original, @existing.reload.email
    assert_equal @existing, membership.reload.user
  end

  test "a directory cannot conscript an account outside the domain it owns" do
    outsider = create(:user, company: create(:company), email: "outsider@elsewhere.test")

    post "/scim/users", headers: scim_headers, params: {
      schemas: [ "urn:ietf:params:scim:schemas:core:2.0:User" ],
      userName: outsider.email, active: true
    }.to_json

    membership = outsider.company_memberships.find_by(company: @company)
    assert_not_nil membership, "the membership is created, as an invitation"
    # But NOT active: acceptance is the person's, exactly as for a hand-written
    # invitation. The directory only proves it owns its own domain.
    assert_equal "invited", membership.state
  end

  test "an unknown token is refused" do
    get "/scim/users", headers: { "Authorization" => "Bearer ascim_not-a-real-token" }

    assert_response :unauthorized
  end

  test "a disabled configuration stops working immediately" do
    @configuration.update!(enabled: false)

    get "/scim/users", headers: scim_headers

    assert_response :unauthorized
  end

  test "using the token records that the directory is alive" do
    get "/scim/users", headers: scim_headers

    assert_not_nil @configuration.reload.last_seen_at
  end
end
