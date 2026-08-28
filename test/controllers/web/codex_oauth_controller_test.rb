# frozen_string_literal: true

require "test_helper"

class Web::CodexOauthControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    Settings.stubs(:codex_oauth).returns(OpenStruct.new(client_id: "aixle-codex-client", issuer: "https://auth.openai.test"))

    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "authorize uses the deployment host, PKCE, and signed user/company state" do
    get codex_oauth_authorize_path

    assert_response :redirect
    uri = URI(response.headers["Location"])
    query = URI.decode_www_form(uri.query).to_h
    assert_equal "auth.openai.test", uri.host
    assert_equal "http://localhost:4000/auth/codex/callback", query["redirect_uri"]
    assert_equal "S256", query["code_challenge_method"]
    assert query["code_challenge"].present?
    refute query.key?("code_verifier")

    payload = Oauth::State.decode(query["state"])
    assert_equal "codex", payload["provider"]
    assert_equal @user.id, payload["user_id"]
    assert_equal @company.id, payload["owner_id"]
  end

  test "callback exchanges once and persists Codex credentials for the correct company" do
    state = state_for(@user, @company)
    tokens = Codex::Api::Tokens.new(access_token: "access-token", refresh_token: "refresh-token", id_token: "id-token")
    Codex::Api.expects(:exchange_authorization_code).with(
      code: "authorization-code",
      code_verifier: "server-only-verifier",
      redirect_uri: "http://localhost:4000/auth/codex/callback",
      client_id: "aixle-codex-client"
    ).returns(tokens)

    assert_difference("AgentCredential.count", 1) do
      get codex_oauth_callback_path, params: { code: "authorization-code", state: state }
    end

    credential = AgentCredential.last
    assert_equal @user, credential.user
    assert_equal @company, credential.company
    assert_equal "codex", credential.agent_type
    assert_equal "access-token", credential.config_data.dig("tokens", "access_token")
    assert_redirected_to profile_path
    assert_equal "Codex authentication saved", flash[:notice]

    assert_no_difference("AgentCredential.count") do
      get codex_oauth_callback_path, params: { code: "authorization-code", state: state }
    end
    assert_equal "This Codex authorization link was already used or expired", flash[:alert]
  end

  test "callback rejects mismatched users without exchanging or persisting" do
    other = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    state = state_for(other, @company)
    Codex::Api.expects(:exchange_authorization_code).never

    assert_no_difference("AgentCredential.count") do
      get codex_oauth_callback_path, params: { code: "authorization-code", state: state }
    end
    assert_equal "Invalid or expired Codex authorization", flash[:alert]
  end

  test "denied callback is actionable and leaves the nonce available for a retry" do
    state = state_for(@user, @company)
    payload = Oauth::State.decode(state)

    get codex_oauth_callback_path, params: { error: "access_denied", state: state }

    assert_equal "Codex authorization was cancelled or denied", flash[:alert]
    assert Oauth::State.consume(payload["nonce"]), "provider errors must not consume the one-time verifier"
  end

  private

  def state_for(user, company)
    Oauth::State.encode(
      owner_type: "Company", owner_id: company.id, user_id: user.id,
      provider: "codex", return_to: profile_path, code_verifier: "server-only-verifier"
    )
  end
end
