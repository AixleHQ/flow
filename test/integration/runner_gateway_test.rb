# frozen_string_literal: true

require "test_helper"

# The runner gateway, /runner/v1/* (docs/design/agent-runtimes/DESIGN.md §6.2,
# §9.2, §9.3): `manual` registration, refresh rotation and unregistration, and
# the checks every request goes through.
class RunnerGatewayTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  REGISTRATION = { name: "build-01", os: "linux", arch: "amd64", facts: { "docker" => "27.1.0" }, ephemeral: false }.freeze

  setup do
    @company = create(:company)
    @runner = create(:runner, :manual, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
  end

  # == POST /runner/v1/register ==

  test "a registration token registers one manual machine and returns its pair once" do
    token = Runners::Credentials.mint_registration!(@runner)

    register(token)

    assert_response :created
    environment = RunnerEnvironment.sole
    body = response.parsed_body
    assert_equal({ "id" => environment.id, "key" => environment.key, "display_name" => "build-01", "state" => "registered" },
                 body["environment"])
    assert_equal %w[registered linux amd64 1.4.0], [ environment.origin, environment.os, environment.arch, environment.runner_version ]
    assert_equal({ "docker" => "27.1.0" }, environment.facts)
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
    assert_equal environment, Runners::Credentials.usable(body["access_token"], kind: :access).runner_environment
    assert_equal environment, RunnerCredential.find_by_token(body["refresh_token"], kind: :refresh).runner_environment

    register(token)
    assert_refused :unauthorized, "invalid_token"
    assert_equal 1, RunnerEnvironment.count
  end

  test "a registration token is refused after an hour" do
    token = Runners::Credentials.mint_registration!(@runner)

    travel 1.hour + 1.second
    register(token)

    assert_refused :unauthorized, "invalid_token"
    assert_equal 0, RunnerEnvironment.count
  end

  test "registration refuses an unknown token, a token of another kind and an ephemeral machine" do
    pair = registered_pair
    token = Runners::Credentials.mint_registration!(@runner)

    register("arreg_not-a-token")
    assert_refused :unauthorized, "invalid_token"
    register(pair["access_token"])
    assert_refused :unauthorized, "invalid_token"
    register(token, REGISTRATION.merge(ephemeral: true))
    assert_refused :unprocessable_entity, "ephemeral_not_supported"
    register(token, REGISTRATION.merge(name: " "))
    assert_refused :unprocessable_entity, "invalid_registration"

    register(token)
    assert_response :created
  end

  # == POST /runner/v1/token ==

  test "a refresh token rotates once, and reusing it revokes the family" do
    first = registered_pair

    refresh(first["refresh_token"])
    assert_response :ok
    second = response.parsed_body
    assert_not_equal first["refresh_token"], second["refresh_token"]

    refresh(first["refresh_token"])
    assert_refused :unauthorized, "credential_reuse_detected"
    assert_equal "credential reuse detected", RunnerEnvironment.sole.state_reason

    refresh(second["refresh_token"])
    assert_refused :unauthorized, "invalid_token"
    unregister(second["access_token"])
    assert_refused :unauthorized, "invalid_token"
  end

  test "rotation refuses an access token and a refresh token unused for 30 days" do
    pair = registered_pair

    refresh(pair["access_token"])
    assert_refused :unauthorized, "invalid_token"

    travel 30.days + 1.second
    refresh(pair["refresh_token"])
    assert_refused :unauthorized, "invalid_token"
  end

  # == DELETE /runner/v1/registration ==

  test "unregistering marks the machine gone and its credentials stop working" do
    pair = registered_pair

    unregister(pair["access_token"])

    assert_response :no_content
    assert RunnerEnvironment.sole.gone?
    unregister(pair["access_token"])
    assert_refused :unauthorized, "invalid_token"
    refresh(pair["refresh_token"])
    assert_refused :unauthorized, "invalid_token"
  end

  test "a credential reaches its own environment only" do
    mine = registered_pair
    theirs = registered_pair(name: "build-02")

    unregister(mine["access_token"])

    assert_response :no_content
    assert RunnerEnvironment.find_by!(display_name: "build-01").gone?
    assert RunnerEnvironment.find_by!(display_name: "build-02").registered?
    refresh(theirs["refresh_token"])
    assert_response :ok
  end

  test "an access token is refused after an hour, and a refresh or registration token is not an access token" do
    pair = registered_pair

    unregister(pair["refresh_token"])
    assert_refused :unauthorized, "invalid_token"
    unregister(Runners::Credentials.mint_registration!(@runner))
    assert_refused :unauthorized, "invalid_token"

    travel 1.hour + 1.second
    unregister(pair["access_token"])
    assert_refused :unauthorized, "invalid_token"
  end

  # == every request ==

  test "with the flag off every endpoint answers runners_disabled, and the credentials stay valid" do
    pair = registered_pair
    token = Runners::Credentials.mint_registration!(@runner)

    with_feature(:external_runners, false, company: @company) do
      register(token)
      assert_refused :forbidden, "runners_disabled"
      refresh(pair["refresh_token"])
      assert_refused :forbidden, "runners_disabled"
      unregister(pair["access_token"])
      assert_refused :forbidden, "runners_disabled"
    end

    register(token)
    assert_response :created
    refresh(pair["refresh_token"])
    assert_response :ok
  end

  # The revocation revokes every credential of the runner (§9.3), so a token
  # that is checked for its own state is refused as invalid. A refresh token is
  # looked up whatever its state, and meets the runner's status.
  test "a revoked or deleted runner gets 401 on every endpoint" do
    pair = registered_pair
    token = Runners::Credentials.mint_registration!(@runner)
    @runner.revoke!

    register(token)
    assert_refused :unauthorized, "invalid_token"
    refresh(pair["refresh_token"])
    assert_refused :unauthorized, "runner_revoked"
    unregister(pair["access_token"])
    assert_refused :unauthorized, "invalid_token"

    deleted = create(:runner, :manual, company: @company)
    deleted_token = Runners::Credentials.mint_registration!(deleted)
    deleted.soft_delete!
    register(deleted_token)
    assert_refused :unauthorized, "invalid_token"
  end

  test "a revocation reaches the gateway within five seconds" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    freeze_time
    pair = registered_pair
    @runner.revoke!

    travel 5.seconds + 0.1
    refresh(pair["refresh_token"])

    assert_refused :unauthorized, "runner_revoked"
  end

  test "an unknown protocol or a missing runner version is refused with a clear error" do
    token = Runners::Credentials.mint_registration!(@runner)

    register(token, headers: { "X-Aixle-Runner-Protocol" => "2" })
    assert_refused :bad_request, "unsupported_protocol"
    assert_match(/speaks runner protocol 1, and the request asked for "2"/, response.parsed_body["message"])
    register(token, headers: { "X-Aixle-Runner-Protocol" => nil })
    assert_refused :bad_request, "unsupported_protocol"
    register(token, headers: { "X-Aixle-Runner-Version" => "latest" })
    assert_refused :bad_request, "invalid_runner_version"

    assert_not RunnerCredential.find_by_token(token, kind: :registration).used?
  end

  test "no token reaches the log" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io, level: :debug)
    Rails.logger.broadcast_to(logger)
    token = Runners::Credentials.mint_registration!(@runner)

    register(token)
    pair = response.parsed_body
    refresh(pair["refresh_token"])
    rotated = response.parsed_body

    assert_match %r{/runner/v1/token}, io.string
    [ token, pair["access_token"], pair["refresh_token"], rotated["access_token"], rotated["refresh_token"] ].each do |secret|
      assert_not_includes io.string, secret
    end
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  private

  def headers_for(token, overrides = {})
    { "Authorization" => "Bearer #{token}", "X-Aixle-Runner-Protocol" => "1",
      "X-Aixle-Runner-Version" => "1.4.0" }.merge(overrides).compact
  end

  def register(token, body = REGISTRATION, headers: {})
    post "/runner/v1/register", params: body, headers: headers_for(token, headers), as: :json
  end

  def refresh(token)
    post "/runner/v1/token", headers: headers_for(token), as: :json
  end

  def unregister(token)
    delete "/runner/v1/registration", headers: headers_for(token), as: :json
  end

  def registered_pair(name: "build-01")
    register(Runners::Credentials.mint_registration!(@runner), REGISTRATION.merge(name: name))
    assert_response :created
    response.parsed_body
  end

  def assert_refused(status, error)
    assert_response status
    assert_equal error, response.parsed_body["error"]
  end
end
