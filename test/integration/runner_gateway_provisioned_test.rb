# frozen_string_literal: true

require "test_helper"

# A machine registering into a row the platform made, and checking in
# (docs/design/agent-runtimes/runner-coder.md §8.4; runner/protocol/PROTOCOL.md
# §5.1, §5.9), through the runner gateway, with a fake provisionable adapter.
class RunnerGatewayProvisionedTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  setup do
    @company = create(:company)
    @runner = create(:runner, :coder, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
    @adapter = with_fake_provisioned_adapter
    @environment = create(:runner_environment, :allocated, runner: @runner, external_id: "ws-1")
    @token = Runners::Credentials.mint_registration!(@runner, environment: @environment)
  end

  def headers_for(token) = { "Authorization" => "Bearer #{token}", "X-Aixle-Runner-Protocol" => "1", "X-Aixle-Runner-Version" => "1.4.0" }

  def register(token = @token, name: "ws-1")
    post "/runner/v1/register", params: { name: name, os: "linux", arch: "amd64", facts: { "docker" => "27.1.0" } },
                                headers: headers_for(token), as: :json
  end

  def check_in(token, body = { facts: { "docker" => "27.1.0" } })
    post "/runner/v1/check-in", params: body, headers: headers_for(token), as: :json
  end

  test "register fills the row the token is bound to, and the check-in that follows makes it idle" do
    register

    assert_response :created
    assert_equal({ "id" => @environment.id, "key" => @environment.key, "display_name" => "ws-1", "state" => "booting" },
                 response.parsed_body["environment"])
    assert_equal 1, RunnerEnvironment.where(runner: @runner).count
    pair = response.parsed_body

    check_in(pair["access_token"])

    assert_response :ok
    assert_equal "idle", @environment.reload.state
    assert_equal "idle", response.parsed_body.dig("environment", "state")
  end

  test "a check-in again leaves an idle environment idle" do
    register
    token = response.parsed_body["access_token"]
    check_in(token)

    check_in(token)

    assert_response :ok
    assert_equal "idle", @environment.reload.state
  end

  test "a check-in that reports a failed preflight fails the environment through the allocator, which tears it down" do
    register
    token = response.parsed_body["access_token"]

    check_in(token, { facts: { "preflight_error" => "the Docker daemon is not reachable: down" } })

    assert_response :ok
    @environment.reload
    assert_equal "gone", @environment.state, "failed, then deleted by its adapter"
    assert_equal "ws-1 cannot run sessions: the Docker daemon is not reachable: down", @environment.state_reason
    assert_includes @adapter.calls.map(&:first), :fail
    check_in(token)
    assert_response :unauthorized
  end

  test "the credentials of an environment that is being torn down, failed or gone are refused, and its token cannot register" do
    register
    token = response.parsed_body["access_token"]
    check_in(token)
    assert_response :ok

    %w[tearing_down failed gone].each do |state|
      @environment.update_columns(state: state)

      check_in(token)

      assert_response :unauthorized, state
      assert_equal "invalid_token", response.parsed_body["error"], state
    end
  end

  test "a token whose row failed before the machine registered is refused, and spends nothing" do
    @environment.update_columns(state: "failed")

    register

    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body["error"]
    assert_not RunnerCredential.find_by_token(@token, kind: :registration).used?
  end
end
