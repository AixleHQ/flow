# frozen_string_literal: true

require "test_helper"

# The in-container credential_process helper pipes this response straight into the AWS
# SDK, so the body must be the bare credential-process document and nothing else.
class CloudCredentialsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @session = create(:terminal_session, :running, user: @user, project: @project)
    @sso = FakeAwsSsoClient.new(region: "us-west-2")
    # Stub the app-owned seam, never the vendor SDK (docs/testing.md R2).
    CloudAuth::AwsSsoClient.stubs(:new).returns(@sso)
  end

  PATH = "/cloud/aws/credentials"

  # == auth ==

  test "rejects a request with no credentials" do
    connect_aws
    post PATH

    assert_response :unauthorized
  end

  test "rejects a wrong cloud key" do
    connect_aws
    post PATH, headers: headers(key: "nope")

    assert_response :unauthorized
  end

  test "rejects an unknown session id" do
    post PATH, headers: { "X-Session-Id" => "0", "X-Cloud-Key" => "whatever" }

    assert_response :unauthorized
  end

  # A finished session must not be able to mint AWS credentials.
  test "rejects a session that is no longer active" do
    connect_aws
    @session.update!(state: "finished")

    post PATH, headers: headers

    assert_response :unauthorized
  end

  test "does not accept the session's mcp_key as the cloud key" do
    connect_aws
    post PATH, headers: headers(key: @session.mcp_key)

    assert_response :unauthorized
  end

  # == vending ==

  test "returns the bare credential_process document for a connected user" do
    connect_aws

    post PATH, headers: headers

    assert_response :success
    assert_equal "application/json", response.media_type
    body = JSON.parse(response.body)
    assert_equal 1, body["Version"]
    assert_equal "ASIAFAKEFAKEFAKE", body["AccessKeyId"]
    assert body["SessionToken"].present?
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, body["Expiration"])
    assert_includes response.body, '"Version":1'
  end

  # Credentials are per (user, company) and the session names the company being billed,
  # so a container must never vend a connection another company made.
  test "does not vend a connection that belongs to another company" do
    other_company = create(:company)
    create(:company_membership, user: @user, company: other_company)
    connect_aws(company: other_company)

    post PATH, headers: headers

    assert_response :conflict
    assert_equal "not_connected", JSON.parse(response.body)["error"]
  end

  # == an auth session starts with nothing connected ==
  #
  # Vending an earlier connection would silently log the user in to the very account they
  # opened the auth session to change, and the connect step — which appears only when the
  # helper reports nothing to vend — would never show.

  test "a connection made before this auth session opened is withheld" do
    connect_aws
    AgentCredential.find_by(user_id: @user.id).update_column(:updated_at, @session.created_at - 1.minute)

    post PATH, headers: headers

    assert_response :conflict
    assert @session.reload.metadata["cloud_connect_requested_at"].present?, "must still show the connect step"
  end

  # Finishing the flow inside this session is what lets the CLI's own verification pass on
  # its first attempt instead of reporting a credential error.
  test "a connection made during this auth session is vended" do
    connect_aws
    AgentCredential.find_by(user_id: @user.id).update_column(:updated_at, @session.created_at + 1.minute)

    post PATH, headers: headers

    assert_response :success
    assert_equal "ASIAFAKEFAKEFAKE", JSON.parse(response.body)["AccessKeyId"]
  end

  test "a working session is unaffected and vends an existing connection" do
    working = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    connect_aws
    AgentCredential.find_by(user_id: @user.id).update_column(:updated_at, working.created_at - 1.minute)

    post PATH, headers: { "X-Session-Id" => working.id.to_s,
                          "X-Cloud-Key" => CloudAuth::SessionKey.generate(working) }

    assert_response :success
  end

  # == failure mapping ==

  test "reports a missing connection as a conflict rather than an auth failure" do
    post PATH, headers: headers

    assert_response :conflict
    assert_equal "not_connected", JSON.parse(response.body)["error"]
  end

  # The helper only runs because something asked for AWS credentials; inside an auth
  # container that something is Claude Code's own Bedrock wizard. So this 409 is the signal
  # that the user just chose Bedrock in the TUI, and it is what opens the connect step.
  test "a missing connection records that this session is asking to connect" do
    post PATH, headers: headers

    assert @session.reload.metadata["cloud_connect_requested_at"].present?
  end

  # The helper retries while the user connects, and every write would be another broadcast.
  test "the connect request is recorded once, not on every retry" do
    post PATH, headers: headers
    first = @session.reload.metadata["cloud_connect_requested_at"]

    post PATH, headers: headers

    assert_equal first, @session.reload.metadata["cloud_connect_requested_at"]
  end

  # A connection that exists but needs no vending is not a request to connect.
  test "a bearer-token connection does not mark the session as asking" do
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code",
                                   { "awsBedrock" => { "region" => "us-east-1", "bearer_token" => "x" } })

    post PATH, headers: headers

    assert_response :conflict
    assert_nil @session.reload.metadata["cloud_connect_requested_at"]
  end

  test "reports an expired client registration as needing re-authorisation" do
    connect_aws(registration_expires_at: 1.day.ago, token_expires_at: 1.minute.from_now)

    post PATH, headers: headers

    assert_response :unauthorized
    assert_equal "reauthorization_required", JSON.parse(response.body)["error"]
  end

  test "reports a bearer-token connection as not vendable" do
    AgentCredential.from_artifacts(@user.id, @company.id, "claude_code",
                                   { "awsBedrock" => { "region" => "us-east-1", "bearer_token" => "x" } })

    post PATH, headers: headers

    assert_response :conflict
  end

  private

  def headers(key: nil)
    { "X-Session-Id" => @session.id.to_s, "X-Cloud-Key" => key || CloudAuth::SessionKey.generate(@session) }
  end

  def connect_aws(token_expires_at: 1.hour.from_now, registration_expires_at: 60.days.from_now,
                  company: @company)
    AgentCredential.from_artifacts(@user.id, company.id, "claude_code", {
      "awsBedrock" => {
        "region" => "us-east-1",
        "profile" => "aixle-bedrock",
        "credential_process" => "/usr/local/bin/aixle-aws-creds",
        "identity_center" => {
          "start_url" => "https://example.awsapps.com/start",
          "sso_region" => "us-west-2",
          "account_id" => "111122223333",
          "role_name" => "BedrockUser",
          "registration" => {
            "client_id" => "live-client-id",
            "client_secret" => "live-client-secret",
            "expires_at" => registration_expires_at.iso8601
          },
          "token" => {
            "access_token" => "live-access-token",
            "refresh_token" => "live-refresh-token",
            "expires_at" => token_expires_at.iso8601
          }
        }
      }
    })
  end
end
