# frozen_string_literal: true

require "test_helper"

# POST /runner/v1/check-in (docs/design/agent-runtimes/DESIGN.md §6.2, §14.4;
# runner/protocol/PROTOCOL.md §5.9): the host runner of a `manual` machine
# reporting itself after a start. The wire is pinned by the conformance
# fixtures in runner/protocol/fixtures/v1/check_in/; these tests check what the
# fixtures cannot see, the machine's record.
class RunnerGatewayCheckInTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  REGISTRATION = { name: "build-01", os: "linux", arch: "amd64", facts: { "docker" => "26.0.0" }, ephemeral: false }.freeze
  AMD64 = "a" * 64

  setup do
    @company = create(:company)
    @runner = create(:runner, :manual, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
    post "/runner/v1/register", params: REGISTRATION, headers: headers_for(Runners::Credentials.mint_registration!(@runner), "X-Aixle-Runner-Version" => "0.1.0"), as: :json
    assert_response :created
    @pair = response.parsed_body
    @environment = RunnerEnvironment.sole
  end

  test "a check-in records the version it is sent over the one the machine registered with, and its os, arch and facts" do
    assert_equal "0.1.0", @environment.runner_version

    check_in(os: "linux", arch: "arm64", facts: { "docker" => "27.2.0", "disk_free_bytes" => 53_687_091_200 },
             headers: { "X-Aixle-Runner-Version" => "0.2.0" })

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    @environment.reload
    assert_equal "0.2.0", @environment.runner_version, "a machine that updated itself shows its new version"
    assert_equal "1", @environment.protocol_version
    assert_equal %w[linux arm64], [ @environment.os, @environment.arch ]
    assert_equal({ "docker" => "27.2.0", "disk_free_bytes" => 53_687_091_200 }, @environment.facts)
  end

  test "the answer carries the environment and the config, and no update under the committed pins" do
    check_in(os: "linux", arch: "amd64", facts: {}, headers: { "X-Aixle-Runner-Version" => "9.0.0" })

    assert_response :ok
    assert_equal({ "environment" => { "id" => @environment.id, "key" => @environment.key, "display_name" => "build-01", "state" => "registered" },
                   "config" => { "upload_max_bytes" => Settings.runners.upload_limit } },
                 response.parsed_body)
  end

  test "a field the report leaves out keeps what the platform has recorded" do
    check_in({})

    assert_response :ok
    @environment.reload
    assert_equal %w[linux amd64], [ @environment.os, @environment.arch ]
    assert_equal({ "docker" => "26.0.0" }, @environment.facts)
    assert_equal "1.4.0", @environment.runner_version, "the version is the request's, always"
  end

  test "facts replace the recorded ones" do
    check_in(facts: { "docker_api" => "1.47" })

    assert_equal({ "docker_api" => "1.47" }, @environment.reload.facts)
  end

  test "an idle machine below the recommended version is offered the update, as the empty poll offers it" do
    pin
    check_in(os: "linux", arch: "amd64", facts: {})

    assert_response :ok
    assert_equal({ "version" => "1.5.0", "sha256" => AMD64 }, response.parsed_body["update"])

    get "/runner/v1/ops", params: { after: 0, wait: 0 }, headers: headers_for(@pair["access_token"])
    assert_equal response.parsed_body["update"], { "version" => "1.5.0", "sha256" => AMD64 }
  end

  test "the update follows the version of the request, and the report's os and arch" do
    pin

    check_in(os: "linux", arch: "amd64", facts: {}, headers: { "X-Aixle-Runner-Version" => "1.5.0" })
    assert_not response.parsed_body.key?("update"), "a machine at the recommended version is offered nothing"

    check_in(os: "linux", arch: "riscv64", facts: {})
    assert_not response.parsed_body.key?("update"), "no binary is pinned for the machine's platform"

    check_in(os: "linux", arch: "amd64", facts: {})
    assert_equal "1.5.0", response.parsed_body.dig("update", "version")
  end

  test "no update while the machine holds a session, and none for a machine that opted out" do
    pin
    create(:runner_session, :holding, environment: @environment)

    check_in(os: "linux", arch: "amd64", facts: {})
    assert_not response.parsed_body.key?("update")

    @environment.update!(current_session_id: nil)
    @environment.update!(auto_update: false)
    check_in(os: "linux", arch: "amd64", facts: {})
    assert_not response.parsed_body.key?("update")

    @environment.update!(auto_update: true)
    @runner.update!(config: { "auto_update" => false })
    check_in(os: "linux", arch: "amd64", facts: {})
    assert_not response.parsed_body.key?("update")
  end

  test "a runner below the platform's minimum is refused, and nothing is recorded" do
    pin

    check_in(os: "linux", arch: "arm64", facts: { "x" => 1 }, headers: { "X-Aixle-Runner-Version" => "1.1.9" })

    assert_refused :bad_request, "runner_version_unsupported"
    assert_match(/minimum 1\.2\.0/, response.parsed_body["message"])
    @environment.reload
    assert_equal "0.1.0", @environment.runner_version
    assert_equal({ "docker" => "26.0.0" }, @environment.facts)
  end

  test "the minimum is checked after the token, so a dead token learns nothing about it" do
    pin

    check_in({ os: "linux" }, token: "aracc_unknown", headers: { "X-Aixle-Runner-Version" => "1.1.9" })

    assert_refused :unauthorized, "invalid_token"
  end

  test "a body of the wrong shape is invalid_check_in and records nothing" do
    [ { os: 5 }, { os: nil }, { arch: [ "amd64" ] }, { arch: "x" * 256 }, { facts: nil }, { facts: [ "docker" ] }, { facts: "docker" } ].each do |body|
      check_in(body)

      assert_refused :unprocessable_entity, "invalid_check_in"
    end
    assert_equal "0.1.0", @environment.reload.runner_version
  end

  test "a version over 255 characters is invalid_check_in, whatever the pins say" do
    check_in({ os: "linux" }, headers: { "X-Aixle-Runner-Version" => "1.0.0+#{'b' * 260}" })

    assert_refused :unprocessable_entity, "invalid_check_in"
  end

  test "a check-in with no body reports nothing but its version" do
    post "/runner/v1/check-in", headers: headers_for(@pair["access_token"]), as: :json

    assert_response :ok
  end

  test "it takes the access token only, and the common refusals apply" do
    check_in({}, token: @pair["refresh_token"])
    assert_refused :unauthorized, "invalid_token"

    check_in({}, headers: { "X-Aixle-Runner-Protocol" => "2" })
    assert_refused :bad_request, "unsupported_protocol"

    FeatureFlag.find_by!(key: "external_runners").overrides.update_all(enabled: false)
    check_in({})
    assert_refused :forbidden, "runners_disabled"
  end

  test "an unregistered machine cannot check in" do
    delete "/runner/v1/registration", headers: headers_for(@pair["access_token"]), as: :json
    assert_response :no_content

    check_in({})

    assert_refused :unauthorized, "invalid_token"
  end

  test "an unregistration that commits after the gateway's check is seen under the lock" do
    environment = RunnerEnvironment.find(@environment.id)
    @environment.update!(state: "gone")

    error = assert_raises(Runners::Credentials::Refused) do
      Runners::CheckIn.check_in!(environment, runner_version: "0.3.0", protocol_version: "1", report: { "os" => "linux" })
    end

    assert_equal "invalid_token", error.reason
    assert_equal "0.1.0", @environment.reload.runner_version
  end

  test "the report is recorded as the service takes it, with named parameters and no request" do
    result = Runners::CheckIn.check_in!(@environment, runner_version: "0.3.0", protocol_version: "1",
                                                      report: { "os" => "linux", "arch" => "arm64", "facts" => { "a" => 1 }, "other" => "ignored" })

    assert_equal "0.3.0", result.environment.runner_version
    assert_equal({ "upload_max_bytes" => Settings.runners.upload_limit }, result.config)
    assert_nil result.update
  end

  private

  def check_in(body = {}, token: @pair["access_token"], headers: {})
    post "/runner/v1/check-in", params: body, headers: headers_for(token, headers), as: :json
  end

  def headers_for(token, overrides = {})
    { "Authorization" => "Bearer #{token}", "X-Aixle-Runner-Protocol" => "1",
      "X-Aixle-Runner-Version" => "1.4.0" }.merge(overrides).compact
  end

  def pin(overrides = {})
    pins = {
      "protocol_supported" => [ 1 ], "min_version" => "1.2.0", "recommended_version" => "1.5.0",
      "download_url" => "https://github.com/AixleHQ/flow/releases/download/runner-v%{version}/aixle-runner-%{platform}",
      "binaries" => { "1.5.0" => { "linux-amd64" => { "sha256" => AMD64 } } }
    }
    Runners::Release.stubs(:pins).returns(Runners::Release.parse(pins.merge(overrides)))
  end

  def assert_refused(status, error)
    assert_response status
    assert_equal error, response.parsed_body["error"]
  end
end
