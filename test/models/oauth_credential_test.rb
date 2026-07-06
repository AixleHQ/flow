# frozen_string_literal: true

require "test_helper"

class OauthCredentialTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @client = OauthClient.create!(
      issuer: "https://sentry.io",
      authorization_endpoint: "https://sentry.io/oauth/authorize/",
      token_endpoint: "https://sentry.io/oauth/token/",
      client_id: "client-123",
      source: "static"
    )
  end

  def build_credential(**overrides)
    OauthCredential.new({ owner: @company, oauth_client: @client, provider: "sentry" }.merge(overrides))
  end

  # --- validations / associations ---

  test "valid with an owner, client and provider" do
    assert build_credential.valid?
  end

  test "requires a provider" do
    cred = build_credential(provider: nil)

    assert_not cred.valid?
    assert_includes cred.errors.attribute_names, :provider
  end

  test "requires an oauth_client" do
    assert_not build_credential(oauth_client: nil).valid?
  end

  test "owner may be a User, Company or Project" do
    assert build_credential(owner: @company).valid?
    assert build_credential(owner: @user).valid?
    project = create(:project, company: @company, owner: @user)
    assert build_credential(owner: project).valid?
  end

  test "mcp_server is optional" do
    cred = build_credential
    assert_nil cred.mcp_server
    assert cred.valid?
  end

  # --- status enum ---

  test "status defaults to pending" do
    assert build_credential.pending?
  end

  test "with_status scope and predicates track the status column" do
    cred = build_credential(status: :active)
    cred.save!

    assert cred.active?
    assert_includes OauthCredential.with_status(:active), cred
  end

  # --- encrypted accessors ---

  test "access_token encrypts at rest and round-trips" do
    cred = build_credential(access_token: "at-123")

    assert_not_nil cred.encrypted_access_token
    assert_not_equal "at-123", cred.encrypted_access_token
    assert_equal "at-123", cred.access_token
  end

  test "refresh_token encrypts at rest and round-trips" do
    cred = build_credential(refresh_token: "rt-123")

    assert_not_nil cred.encrypted_refresh_token
    assert_equal "rt-123", cred.refresh_token
  end

  test "blank tokens store nil" do
    cred = build_credential(access_token: "", refresh_token: nil)

    assert_nil cred.encrypted_access_token
    assert_nil cred.encrypted_refresh_token
  end

  test "access_token returns nil when the ciphertext is tampered" do
    cred = build_credential(access_token: "at-123")
    cred.save!
    cred.update_column(:encrypted_access_token, "garbage")

    assert_nil cred.reload.access_token
  end

  # --- expired? ---

  test "expired? is true when the access token is blank" do
    assert build_credential(access_token: nil).expired?
  end

  test "expired? is false when a token is present and there is no expiry" do
    assert_not build_credential(access_token: "at", expires_at: nil).expired?
  end

  test "expired? is true within the skew of expiry" do
    assert build_credential(access_token: "at", expires_at: 5.minutes.from_now).expired?(10.minutes)
  end

  test "expired? is false beyond the skew" do
    assert_not build_credential(access_token: "at", expires_at: 30.minutes.from_now).expired?(10.minutes)
  end

  # --- refreshable? ---

  test "refreshable? requires both a refresh token and a client" do
    assert build_credential(refresh_token: "rt").refreshable?
    assert_not build_credential(refresh_token: nil).refreshable?
  end

  # --- apply_token_response! ---

  test "apply_token_response! persists tokens, expiry, scopes, metadata and activates" do
    cred = build_credential
    cred.apply_token_response!(
      "access_token" => "at-1", "refresh_token" => "rt-1", "token_type" => "Bearer",
      "scope" => "org:read", "expires_in" => 3600, "user" => { "id" => "u1" }
    )
    cred.reload

    assert_equal "at-1", cred.access_token
    assert_equal "rt-1", cred.refresh_token
    assert_equal "org:read", cred.scopes
    assert cred.active?
    assert_in_delta 3600, (cred.expires_at - Time.current), 5
    assert_equal({ "id" => "u1" }, cred.metadata["user"])
    assert_not_nil cred.last_refreshed_at
  end

  test "apply_token_response! never persists bearer material (id_token/secrets) into plaintext metadata" do
    cred = build_credential
    cred.apply_token_response!(
      "access_token" => "at", "refresh_token" => "rt",
      "id_token" => "eyJ-usable-jwt", "some_secret" => "leak",
      "account" => { "id" => "acc" }
    )
    cred.reload

    assert_nil cred.metadata["id_token"], "id_token (a usable JWT) must not land in plaintext metadata"
    assert_nil cred.metadata["some_secret"]
    assert_nil cred.metadata["access_token"]
    assert_equal({ "id" => "acc" }, cred.metadata["account"]) # safe account info is still captured
  end

  test "apply_token_response! keeps an existing refresh_token when the response omits one" do
    cred = build_credential(refresh_token: "rt-old")
    cred.save!

    cred.apply_token_response!("access_token" => "at-new")

    assert_equal "rt-old", cred.reload.refresh_token
    assert_equal "at-new", cred.access_token
  end

  test "apply_token_response! nils expires_at when expires_in is absent" do
    cred = build_credential(expires_at: 1.hour.from_now)

    cred.apply_token_response!("access_token" => "at")

    assert_nil cred.reload.expires_at
  end

  test "apply_token_response! defaults token_type to Bearer" do
    cred = build_credential

    cred.apply_token_response!("access_token" => "at")

    assert_equal "Bearer", cred.reload.token_type
  end

  test "apply_token_response! clears a prior refresh_error and reactivates" do
    cred = build_credential
    cred.save!
    cred.mark_refresh_error!("boom")
    assert cred.error?

    cred.apply_token_response!("access_token" => "at")

    assert cred.active?
    assert_nil cred.reload.refresh_error
  end

  # --- mark_refresh_error! ---

  test "mark_refresh_error! sets error status and truncates the message" do
    cred = build_credential
    cred.save!

    cred.mark_refresh_error!("x" * 600)

    assert cred.reload.error?
    assert_equal 500, cred.refresh_error.length
  end

  # --- upsert_from_token! ---

  test "upsert_from_token! creates an active credential from a token response" do
    cred = OauthCredential.upsert_from_token!(
      owner: @company, oauth_client: @client, provider: "sentry",
      token_response: { "access_token" => "at", "refresh_token" => "rt", "expires_in" => 3600 }
    )

    assert cred.persisted?
    assert cred.active?
    assert_equal "at", cred.access_token
  end

  test "upsert_from_token! is idempotent on the unique owner/client/provider/server key" do
    2.times do |i|
      OauthCredential.upsert_from_token!(
        owner: @company, oauth_client: @client, provider: "sentry",
        token_response: { "access_token" => "at-#{i}" }
      )
    end

    scope = OauthCredential.where(owner: @company, oauth_client: @client, provider: "sentry", mcp_server_id: nil)
    assert_equal 1, scope.count
    assert_equal "at-1", scope.first.access_token
  end

  test "upsert_from_token! keeps a server-attached credential separate from a bare one" do
    server = create(:mcp_server, scope: @company)
    OauthCredential.upsert_from_token!(
      owner: @company, oauth_client: @client, provider: "sentry",
      token_response: { "access_token" => "a" }
    )
    OauthCredential.upsert_from_token!(
      owner: @company, oauth_client: @client, provider: "sentry", mcp_server: server,
      token_response: { "access_token" => "b" }
    )

    assert_equal 2, OauthCredential.where(owner: @company, oauth_client: @client, provider: "sentry").count
  end

  # --- scopes ---

  test "for_owner filters to a single owner" do
    mine = build_credential(owner: @company)
    mine.save!
    other = create(:company)
    theirs = build_credential(owner: other)
    theirs.save!

    assert_includes OauthCredential.for_owner(@company), mine
    assert_not_includes OauthCredential.for_owner(@company), theirs
  end

  test "for_mcp_server filters to credentials attached to that server" do
    server = create(:mcp_server, scope: @company)
    attached = build_credential(mcp_server: server)
    attached.save!
    detached = build_credential
    detached.save!

    assert_includes OauthCredential.for_mcp_server(server), attached
    assert_not_includes OauthCredential.for_mcp_server(server), detached
  end

  test "refresh_due returns only active, refreshable credentials expiring inside the window" do
    due = build_credential(provider: "due", status: :active, refresh_token: "rt", expires_at: 5.minutes.from_now)
    due.save!
    far = build_credential(provider: "far", status: :active, refresh_token: "rt", expires_at: 1.hour.from_now)
    far.save!
    no_refresh = build_credential(provider: "norefresh", status: :active, refresh_token: nil,
                                  expires_at: 5.minutes.from_now)
    no_refresh.save!
    not_active = build_credential(provider: "pending", status: :pending, refresh_token: "rt",
                                  expires_at: 5.minutes.from_now)
    not_active.save!
    null_expiry = build_credential(provider: "nullexp", status: :active, refresh_token: "rt", expires_at: nil)
    null_expiry.save!

    result = OauthCredential.refresh_due
    assert_includes result, due
    assert_not_includes result, far
    assert_not_includes result, no_refresh
    assert_not_includes result, not_active
    assert_not_includes result, null_expiry
  end

  test "refresh_due honors a custom window argument" do
    cred = build_credential(provider: "custom", status: :active, refresh_token: "rt", expires_at: 45.minutes.from_now)
    cred.save!

    assert_not_includes OauthCredential.refresh_due, cred
    assert_includes OauthCredential.refresh_due(1.hour), cred
  end
end
