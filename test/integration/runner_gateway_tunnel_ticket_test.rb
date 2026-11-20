# frozen_string_literal: true

require "test_helper"

# POST /runner/v1/tunnel-ticket (docs/design/agent-runtimes/runner-relay.md §3.1;
# runner/protocol/PROTOCOL.md §5.11). The wire is pinned by the conformance fixtures in
# runner/protocol/fixtures/v1/tunnel_ticket/; these tests check the claims of the ticket
# and what the fixtures cannot see.
class RunnerGatewayTunnelTicketTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  KEY = "a-ticket-key-of-32-characters-xx"

  setup do
    @company = create(:company)
    @runner = create(:runner, :manual, company: @company)
    @project = create(:project, :standalone, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
    post "/runner/v1/register", params: { name: "build-01", os: "linux", arch: "amd64", facts: {} },
                                headers: headers_for(Runners::Credentials.mint_registration!(@runner)), as: :json
    assert_response :created
    @pair = response.parsed_body
    @environment = RunnerEnvironment.sole
    Settings.runners.relay.stubs(:ticket_key).returns(KEY)
    Runners::TunnelTicket.stubs(:mode).returns("session")
  end

  test "a machine that holds a session gets a ticket for it, and nothing is cached" do
    session = hold_session

    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["access_token"])

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    assert_equal %w[expires_at ticket], body.keys.sort
    assert_match(/\Aartun_[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z/, body["ticket"])
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, body["expires_at"])

    claims = JSON.parse(Base64.urlsafe_decode64(body["ticket"].delete_prefix("artun_").split(".").first))
    assert_equal({ "v" => 1, "e" => @environment.id, "r" => @runner.id, "s" => session.id }, claims.slice("v", "e", "r", "s"))
    assert_equal Time.iso8601(body["expires_at"]).to_i, claims["exp"]
    assert_in_delta 60, claims["exp"] - Time.current.to_i, 2
  end

  test "an idle machine is answered 409 no_session, with nothing but the refusal" do
    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["access_token"])

    assert_response :conflict
    assert_equal "no_session", response.parsed_body["error"]
    assert_equal %w[error message], response.parsed_body.keys.sort
  end

  test "a platform that does not offer the tunnel answers 404 not_found" do
    Runners::TunnelTicket.stubs(:mode).returns("")
    hold_session

    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["access_token"])

    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]
  end

  test "the standard check order: headers, then the token, then the machine's session" do
    post "/runner/v1/tunnel-ticket", headers: headers_for("aracc_not-a-token", "X-Aixle-Runner-Protocol" => "2")
    assert_response :bad_request
    assert_equal "unsupported_protocol", response.parsed_body["error"]

    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["access_token"], "X-Aixle-Runner-Version" => "latest")
    assert_equal "invalid_runner_version", response.parsed_body["error"]

    post "/runner/v1/tunnel-ticket", headers: headers_for("aracc_not-a-token")
    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body["error"]

    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["refresh_token"])
    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body["error"]
  end

  test "a revoked runner and a flag turned off are the gateway's own refusals" do
    hold_session
    FeatureFlag.find_by!(key: "external_runners").overrides.sole.update!(enabled: false)

    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["access_token"])
    assert_response :forbidden
    assert_equal "runners_disabled", response.parsed_body["error"]

    FeatureFlag.find_by!(key: "external_runners").overrides.sole.update!(enabled: true)
    @runner.revoke!
    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["access_token"])
    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body["error"]
  end

  test "a ticket request is a sign of life, like any request of a machine" do
    hold_session
    @environment.update_columns(last_heartbeat_at: 1.hour.ago)

    post "/runner/v1/tunnel-ticket", headers: headers_for(@pair["access_token"])

    assert_response :ok
    assert_operator @environment.reload.last_heartbeat_at, :>, 1.minute.ago
  end

  test "the check-in tells the runner about the tunnel when the platform offers it, and nothing when it does not" do
    post "/runner/v1/check-in", params: { os: "linux", arch: "amd64", facts: {} }, headers: headers_for(@pair["access_token"]), as: :json
    assert_equal({ "mode" => "session", "path" => "/runner/v1/tunnel" }, response.parsed_body.dig("config", "tunnel"))
    assert_equal Settings.runners.upload_limit, response.parsed_body.dig("config", "upload_max_bytes")

    Runners::TunnelTicket.stubs(:mode).returns("")
    post "/runner/v1/check-in", params: { os: "linux", arch: "amd64", facts: {} }, headers: headers_for(@pair["access_token"]), as: :json
    assert_equal({ "upload_max_bytes" => Settings.runners.upload_limit }, response.parsed_body["config"])
  end

  private

  def hold_session
    session = create(:terminal_session, :agent_session, user: @project.owner, project: @project, runner: @runner,
                                                        runner_environment: @environment, mode: "non_interactive",
                                                        initial_prompt: "go")
    @environment.update!(current_session_id: session.id)
    session
  end

  def headers_for(token, overrides = {})
    { "Authorization" => "Bearer #{token}", "X-Aixle-Runner-Protocol" => "1",
      "X-Aixle-Runner-Version" => "1.4.0" }.merge(overrides).compact
  end
end
