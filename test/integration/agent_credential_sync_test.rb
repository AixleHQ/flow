# frozen_string_literal: true

require "test_helper"

# The in-container watcher posts here as soon as the CLI rotates its token, so the stored
# credential stops being the stale copy — which is what makes a container that dies without
# cleanup survivable.
class AgentCredentialSyncTest < ActionDispatch::IntegrationTest
  PATH = "/agents/credentials"
  CREDENTIALS_FILE = "/home/claude/.claude/.credentials.json"

  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project,
                                                   company_id: @company.id, agent_type: "claude_code",
                                                   session_type: "agent_session")
    @credential = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", {
      "claudeAiOauth" => { "accessToken" => "at-old", "refreshToken" => "rt-old",
                           "expiresAt" => (1.hour.from_now.to_f * 1000).to_i }
    })
  end

  def headers(key: Agents::SessionKey.generate(@session), session_id: @session.id)
    { "X-Session-Id" => session_id.to_s, "X-Agent-Key" => key, "CONTENT_TYPE" => "application/json" }
  end

  def rotated_body(access_token: "at-new", refresh_token: "rt-new", expires_at: 8.hours.from_now)
    {
      files: {
        CREDENTIALS_FILE => {
          claudeAiOauth: { accessToken: access_token, refreshToken: refresh_token,
                           expiresAt: (expires_at.to_f * 1000).to_i }
        }.to_json
      }
    }.to_json
  end

  # == auth ==

  test "rejects a request with no key" do
    post PATH, params: rotated_body, headers: { "X-Session-Id" => @session.id.to_s, "CONTENT_TYPE" => "application/json" }

    assert_response :unauthorized
  end

  test "rejects a wrong key" do
    post PATH, params: rotated_body, headers: headers(key: "nope")

    assert_response :unauthorized
  end

  test "rejects an unknown session" do
    post PATH, params: rotated_body, headers: headers(session_id: 0, key: "whatever")

    assert_response :unauthorized
  end

  # A finished session must not be able to overwrite a credential the user may have
  # re-authenticated since.
  test "rejects a session that is no longer active" do
    @session.update!(state: "finished")

    post PATH, params: rotated_body, headers: headers

    assert_response :unauthorized
    assert_equal "at-old", @credential.reload.config_data.dig("claudeAiOauth", "accessToken")
  end

  # A key minted for one session must not work for another.
  test "rejects a key derived from a different session" do
    other = create(:terminal_session, :running, user: @user, project: @project,
                                                company_id: @company.id, agent_type: "claude_code",
                                                session_type: "agent_session")

    post PATH, params: rotated_body, headers: headers(key: Agents::SessionKey.generate(other))

    assert_response :unauthorized
  end

  # == persistence ==

  test "stores a token the container rotated" do
    post PATH, params: rotated_body, headers: headers

    assert_response :no_content
    stored = @credential.reload.config_data.fetch("claudeAiOauth")
    assert_equal "at-new", stored["accessToken"]
    assert_equal "rt-new", stored["refreshToken"]
  end

  test "an unchanged file is accepted and changes nothing" do
    post PATH, params: rotated_body(access_token: "at-old", refresh_token: "rt-old",
                                    expires_at: Time.zone.at(@credential.expires_at)),
               headers: headers

    assert_response :no_content
    assert_equal "at-old", @credential.reload.config_data.dig("claudeAiOauth", "accessToken")
  end

  # The adapter's merge refuses to downgrade: a post that was in flight while a
  # server-side refresh landed must not put the older token back.
  test "does not overwrite a newer stored token with an older one" do
    @credential.update!(config_data: {
      "claudeAiOauth" => { "accessToken" => "at-newer", "refreshToken" => "rt-newer",
                           "expiresAt" => (8.hours.from_now.to_f * 1000).to_i }
    })

    post PATH, params: rotated_body(access_token: "at-stale", expires_at: 10.minutes.from_now), headers: headers

    assert_response :no_content
    assert_equal "at-newer", @credential.reload.config_data.dig("claudeAiOauth", "accessToken")
  end

  test "ignores a path this agent does not own" do
    body = { files: { "/etc/passwd" => "root:x:0:0" } }.to_json

    post PATH, params: body, headers: headers

    assert_response :unprocessable_entity
    assert_equal "at-old", @credential.reload.config_data.dig("claudeAiOauth", "accessToken")
  end

  test "refuses a body larger than the cap" do
    body = { files: { CREDENTIALS_FILE => "x" * (AgentCredentialSyncController::MAX_BODY_BYTES + 1) } }.to_json

    post PATH, params: body, headers: headers

    assert_response :content_too_large
  end

  # An auth_setup session is a login in progress; AgentAuthStrategy owns what it captures,
  # including the rule that a design re-login must not resurrect a stale base block.
  test "refuses a write-back from an auth session" do
    @session.update!(session_type: "auth_setup")

    post PATH, params: rotated_body, headers: headers

    assert_response :conflict
    assert_equal "at-old", @credential.reload.config_data.dig("claudeAiOauth", "accessToken")
  end

  test "answers not_found when the session's company has no credential for the agent" do
    @credential.destroy!

    post PATH, params: rotated_body, headers: headers

    assert_response :not_found
  end
end
