# frozen_string_literal: true

# What the Bitbucket Forge tests need from Atlassian's side: a signing key
# served as the Forge JWKS, invocation tokens signed with it, the app tokens
# Forge pushes, and Bitbucket's answers to the few calls the app makes outside a
# project connection. Included by the test classes that use it.
module ForgeTestHelper
  FORGE_KID = "forge-test-key"
  FORGE_KEY = OpenSSL::PKey::RSA.new(2048)
  FORGE_WORKSPACE_UUID = "{8f1d6b2a-0000-4000-8000-00000000b17b}"
  FORGE_ADMIN_ACCOUNT = "712020:3c1b6f7e-admin"

  def stub_forge_keys!(kid: FORGE_KID)
    jwk = JWT::JWK.new(FORGE_KEY.public_key, kid: kid).export
    stub_request(:get, Bitbucket::AppConfig::DEFAULT_JWKS_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { keys: [ jwk ] }.to_json)
  end

  def forge_installation_ari = "ari:cloud:ecosystem::installation/#{SecureRandom.uuid}"

  # Claims shaped like the invocation contract's example; `claims` overrides any of them.
  def forge_invocation_token(installation_id:, workspace_uuid: FORGE_WORKSPACE_UUID, principal: nil,
                             key: FORGE_KEY, kid: FORGE_KID, algorithm: "RS256", **claims)
    payload = {
      app: {
        id: BitbucketTestHelper::FORGE_APP_ID, appVersion: "2.0.0", installationId: installation_id,
        apiBaseUrl: "https://api.bitbucket.org",
        installation: { id: installation_id,
                        contexts: [ { name: "bitbucket", apiBaseUrl: "https://api.bitbucket.org",
                                      workspaceId: workspace_uuid.delete("{}") } ] },
        environment: { type: "PRODUCTION", id: "ari:cloud:ecosystem::environment/#{BitbucketTestHelper::FORGE_ENVIRONMENT_ID}" },
        module: { type: "core:endpoint", key: "heartbeat" }
      },
      context: {}, principal: principal,
      aud: BitbucketTestHelper::FORGE_APP_ID, iss: "forge/invocation-token",
      iat: Time.current.to_i, nbf: Time.current.to_i, exp: 25.seconds.from_now.to_i, jti: SecureRandom.uuid
    }.deep_merge(claims).compact
    JWT.encode(payload.deep_stringify_keys, key, algorithm, { kid: kid })
  end

  # Opaque to Forge's documentation, a JWT in practice; only `exp` is read.
  def forge_system_token(expires_at: 2.hours.from_now)
    encode = ->(hash) { Base64.urlsafe_encode64(hash.to_json, padding: false) }
    "#{encode.call(alg: 'RS256')}.#{encode.call(exp: expires_at.to_i, sub: SecureRandom.hex(4))}.#{SecureRandom.hex(16)}"
  end

  def forge_headers(token, system_token: forge_system_token)
    { "Authorization" => "Bearer #{token}", "x-forge-oauth-system" => system_token, "Content-Type" => "application/json" }
  end

  def stub_workspace_permission(installation, account_id: FORGE_ADMIN_ACCOUNT, permission: "owner")
    values = permission ? [ { permission: permission, user: { account_id: account_id, display_name: "Ada" } } ] : []
    stub_request(:get, "#{BitbucketTestHelper::BITBUCKET_API}/workspaces/#{ERB::Util.url_encode(installation.workspace_uuid)}/permissions")
      .with(query: { "q" => %(user.account_id="#{account_id}") })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { pagelen: 10, page: 1, size: values.size, values: values }.to_json)
  end

  def stub_workspace_repositories(installation, status: 200)
    stub_request(:get, "#{BitbucketTestHelper::BITBUCKET_API}/repositories/#{ERB::Util.url_encode(installation.workspace_uuid)}")
      .with(query: { "pagelen" => "1" })
      .to_return(status: status, headers: { "Content-Type" => "application/json" },
                 body: { pagelen: 1, values: [ { full_name: "#{installation.workspace_slug}/api" } ] }.to_json)
  end
end
