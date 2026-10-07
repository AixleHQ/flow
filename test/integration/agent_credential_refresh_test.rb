# frozen_string_literal: true

require "test_helper"

# The in-container proxy hands the CLI's OAuth refresh here (Agents::RefreshBroker), so every
# container of one login refreshes under one lock instead of each spending the same single-use
# refresh token.
class AgentCredentialRefreshTest < ActionDispatch::IntegrationTest
  PATH = "/agents/credentials/refresh"
  TOKEN_URL = Agents::ClaudeCodeAdapter::OAUTH_TOKEN_URL

  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project,
                                                   company_id: @company.id, agent_type: "claude_code",
                                                   session_type: "workflow_step")
    @credential = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login("at-1", "rt-1", 4.minutes))
  end

  def login(access_token, refresh_token, expires_in)
    { "claudeAiOauth" => { "accessToken" => access_token, "refreshToken" => refresh_token,
                           "expiresAt" => (expires_in.from_now.to_f * 1000).to_i, "scopes" => %w[user:inference] } }
  end

  def headers(key: Agents::SessionKey.generate(@session))
    { "X-Session-Id" => @session.id.to_s, "X-Agent-Key" => key, "CONTENT_TYPE" => "application/json" }
  end

  # The request Claude Code 2.1.281 sends: JSON, with its own client id and scopes.
  def cli_refresh(refresh_token, url: TOKEN_URL)
    { url: url, content_type: "application/json",
      token_request: { grant_type: "refresh_token", refresh_token: refresh_token,
                       client_id: Agents::ClaudeCodeAdapter::BASE_OAUTH_CLIENT_ID, scope: "user:inference" }.to_json }.to_json
  end

  # The forwarded request carries the refresh token itself.
  test "the forwarded request is filtered out of the request log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal "[FILTERED]", filter.filter("token_request" => "grant_type=refresh_token&refresh_token=rt")["token_request"]
  end

  test "rejects a request without the session's key" do
    post PATH, params: cli_refresh("rt-1"), headers: headers(key: "nope")

    assert_response :unauthorized
  end

  test "refreshes a token it still holds and answers with the new pair" do
    stub_request(:post, TOKEN_URL)
      .with(body: hash_including("refresh_token" => "rt-1"))
      .to_return(status: 200, body: { access_token: "at-2", refresh_token: "rt-2", expires_in: 28_800 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    assert_enqueued_with(job: Agents::CredentialFanOutJob, args: [ @credential.id, @session.id ]) do
      post PATH, params: cli_refresh("rt-1"), headers: headers
    end

    answer = served
    assert_equal "at-2", answer["access_token"]
    assert_equal "rt-2", answer["refresh_token"]
    assert_in_delta 28_800, answer["expires_in"], 5
    assert_equal "rt-2", @credential.reload.config_data.dig("claudeAiOauth", "refreshToken")
  end

  # The second container asking with the token the first one spent: on a laptop the CLI's
  # lockfile gives it the first one's result, and so does this.
  test "answers a token it already replaced with the tokens that replaced it, without asking the vendor" do
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login("at-2", "rt-2", 8.hours))

    post PATH, params: cli_refresh("rt-1"), headers: headers

    answer = served
    assert_equal "at-2", answer["access_token"]
    assert_equal "rt-2", answer["refresh_token"]
    assert_not_requested :post, TOKEN_URL
  end

  test "refreshes the current pair when the one that replaced the token is itself about to expire" do
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login("at-2", "rt-2", 3.minutes))
    stub_request(:post, TOKEN_URL)
      .with(body: hash_including("refresh_token" => "rt-2"))
      .to_return(status: 200, body: { access_token: "at-3", refresh_token: "rt-3", expires_in: 28_800 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    post PATH, params: cli_refresh("rt-1"), headers: headers

    assert_equal "at-3", served["access_token"]
  end

  test "tells the CLI a grant the vendor refused is dead, and condemns the credential" do
    stub_request(:post, TOKEN_URL).to_return(status: 400, body: { error: "invalid_grant" }.to_json)

    post PATH, params: cli_refresh("rt-1"), headers: headers

    assert_response :ok
    assert_equal 400, response.parsed_body["status"]
    assert_equal "invalid_grant", JSON.parse(response.parsed_body["body"])["error"]
    assert_equal "error", @credential.reload.status
  end

  # A login made inside the container: not ours to answer for.
  test "lets a refresh token it never held through to the vendor" do
    post PATH, params: cli_refresh("rt-from-a-fresh-login"), headers: headers

    assert_response :no_content
    assert_not_requested :post, TOKEN_URL
  end

  test "lets a request to an endpoint it does not broker through" do
    post PATH, params: cli_refresh("rt-1", url: "https://example.com/oauth/token"), headers: headers

    assert_response :no_content
  end

  test "lets any other grant through" do
    body = { url: TOKEN_URL, content_type: "application/json",
             token_request: { grant_type: "authorization_code", code: "c" }.to_json }.to_json

    post PATH, params: body, headers: headers

    assert_response :no_content
  end

  test "lets the request through when the vendor cannot be reached" do
    stub_request(:post, TOKEN_URL).to_timeout

    post PATH, params: cli_refresh("rt-1"), headers: headers

    assert_response :no_content
    assert_equal "active", @credential.reload.status
  end

  private

  def served
    assert_response :ok
    assert_equal 200, response.parsed_body["status"]
    JSON.parse(response.parsed_body["body"])
  end
end
