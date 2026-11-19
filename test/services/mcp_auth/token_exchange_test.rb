# frozen_string_literal: true

require "test_helper"

class MCPAuth::TokenExchangeTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @client = MCPAuth::Client.new(client_id: "aocl_test", kind: "dcr", name: "Test app", host: nil,
                                  redirect_uris: [ "http://localhost/cb" ])
    @verifier = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
    @grant, @code = MCPAuthGrant.authorize!(user: @user, client: @client, redirect_uri: "http://localhost:4100/cb",
                                            code_challenge: challenge, resource: nil, scope: "mcp",
                                            proof_provider_ids: [ IdentityProvider.password.id ])
  end

  def exchange(**params)
    MCPAuth::TokenExchange.call({ "grant_type" => "authorization_code", "code" => @code, "client_id" => "aocl_test",
                                  "code_verifier" => @verifier }.merge(params.stringify_keys))
  end

  def refresh(token) = MCPAuth::TokenExchange.call("grant_type" => "refresh_token", "refresh_token" => token)

  def assert_error(code, &)
    error = assert_raises(MCPAuth::TokenExchange::Error, &)
    assert_equal code, error.code
    error
  end

  test "a code exchanged in time gives a token pair that authenticates as the grant" do
    tokens = exchange

    assert_equal @grant, MCPAuthToken.authenticate(tokens[:access_token])
    assert_equal "mcp", tokens[:scope]
    assert_operator @grant.reload.expires_at, :>, 29.days.from_now
  end

  test "an expired code, another client's code, and a wrong redirect_uri are refused" do
    assert_error("invalid_grant") { exchange("client_id" => "aocl_other") }
    assert_error("invalid_grant") { exchange("redirect_uri" => "http://localhost:4100/other") }

    travel MCPAuthGrant::CODE_TTL + 1.second
    assert_error("invalid_grant") { exchange }
  end

  test "an access token stops working when its user leaves, and when it expires" do
    access = exchange[:access_token]

    @user.update_columns(deleted_at: Time.current)
    assert_nil MCPAuthToken.authenticate(access)
    @user.update_columns(deleted_at: nil)

    travel MCPAuthToken::ACCESS_TTL + 1.second
    assert_nil MCPAuthToken.authenticate(access)
  end

  test "a refresh token rotates; a retry right after still works, a replay later ends the grant" do
    first = exchange
    second = refresh(first[:refresh_token])
    assert_not_equal first[:refresh_token], second[:refresh_token]

    travel 5.seconds
    retried = refresh(first[:refresh_token])
    assert MCPAuthToken.authenticate(retried[:access_token])

    travel MCPAuthToken::REUSE_GRACE + 1.second
    error = assert_error("invalid_grant") { refresh(first[:refresh_token]) }
    assert_match(/already used/, error.message)
    assert @grant.reload.revoked?
    assert_nil MCPAuthToken.authenticate(second[:access_token])
  end

  test "an unknown grant type, a missing one, and a stranger's refresh token are told apart" do
    assert_error("unsupported_grant_type") { MCPAuth::TokenExchange.call("grant_type" => "password") }
    assert_error("invalid_request") { MCPAuth::TokenExchange.call({}) }
    assert_error("invalid_grant") { refresh("aort_not-a-token") }
  end
end
