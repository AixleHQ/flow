# frozen_string_literal: true

require "test_helper"

# The runner release endpoints, the version skew policy and the update offer
# (docs/design/agent-runtimes/DESIGN.md §14.2 to §14.4, runner/protocol/PROTOCOL.md
# §5.1, §5.4, §5.6, §5.7): the platform's pins, the `runners.release` block of
# config/settings.yml, decide what the gateway serves, whom it registers and
# what it recommends.
class RunnerGatewayReleasesTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  REGISTRATION = { name: "build-01", os: "linux", arch: "amd64", facts: {}, ephemeral: false }.freeze
  AMD64 = "a" * 64
  ARM64 = "b" * 64
  ASSET = "https://github.com/AixleHQ/flow/releases/download/runner-v1.5.0/aixle-runner-linux-amd64"

  setup do
    @company = create(:company)
    @runner = create(:runner, :manual, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true, reason: "test")
  end

  def pin(overrides = {})
    pins = {
      "protocol_supported" => [ 1 ], "min_version" => "1.2.0", "recommended_version" => "1.5.0",
      "download_url" => "https://github.com/AixleHQ/flow/releases/download/runner-v%{version}/aixle-runner-%{platform}",
      "binaries" => { "1.5.0" => { "linux-amd64" => { "sha256" => AMD64 }, "linux-arm64" => { "sha256" => ARM64 } } }
    }
    Runners::Release.stubs(:pins).returns(Runners::Release.parse(pins.merge(overrides)))
  end

  # == GET /runner/v1/releases/:version/:platform ==

  test "a pinned binary redirects to its release asset with the pinned digest, with no token or protocol headers" do
    pin

    get "/runner/v1/releases/1.5.0/linux-amd64"

    assert_response :found
    assert_equal ASSET, response.headers["Location"]
    assert_equal AMD64, response.headers["X-Aixle-Runner-Sha256"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
  end

  test "an unpinned version or platform is not found, and a malformed one is an invalid request" do
    pin

    get "/runner/v1/releases/1.4.0/linux-amd64"
    assert_refused :not_found, "not_found"
    get "/runner/v1/releases/1.5.0/darwin-arm64"
    assert_refused :not_found, "not_found"
    get "/runner/v1/releases/v1.5.0/linux-amd64"
    assert_refused :bad_request, "invalid_request"
    get "/runner/v1/releases/1.5.0/linux"
    assert_refused :bad_request, "invalid_request"
    assert_nil response.headers["X-Aixle-Runner-Sha256"]
  end

  # PROTOCOL.md §2: a cached refusal would outlive the deploy that pins the version.
  test "every refusal of the release endpoints is no-store" do
    pin

    [ "/runner/v1/releases/1.4.0/linux-amd64", "/runner/v1/releases/1.4.0/checksums",
      "/runner/v1/releases/v1.5.0/linux-amd64", "/runner/v1/releases/v1.5.0/checksums" ].each do |path|
      get path

      assert_includes [ 400, 404 ], response.status, path
      assert_equal "no-store", response.headers["Cache-Control"], path
    end
  end

  test "a version with a pre-release and build metadata is routed whole" do
    pin("binaries" => { "1.5.0" => { "linux-amd64" => { "sha256" => AMD64 } },
                        "1.6.0-rc.1+build.7" => { "linux-amd64" => { "sha256" => ARM64 } } })

    get "/runner/v1/releases/1.6.0-rc.1+build.7/linux-amd64"

    assert_response :found
    assert_equal ARM64, response.headers["X-Aixle-Runner-Sha256"]
    assert_equal "https://github.com/AixleHQ/flow/releases/download/runner-v1.6.0-rc.1+build.7/aixle-runner-linux-amd64",
                 response.headers["Location"]
  end

  # == GET /runner/v1/releases/:version/checksums ==

  test "the checksums are the pinned digests of the version" do
    pin

    get "/runner/v1/releases/1.5.0/checksums"

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal({ "version" => "1.5.0",
                   "binaries" => { "linux-amd64" => { "sha256" => AMD64 }, "linux-arm64" => { "sha256" => ARM64 } } },
                 response.parsed_body)
    get "/runner/v1/releases/1.4.0/checksums"
    assert_refused :not_found, "not_found"
  end

  # The committed pins, not a stub: runner-v0.1.0 and the digests of its
  # checksums.txt.
  test "with the committed pins 0.1.0 is served with the released digests" do
    { "linux-amd64" => "55af0ecb22c70f52ca4213f7f310c6321ba0e1d175545f663c1c948107caad44",
      "linux-arm64" => "e27d43e8d29ec520f5868b4394d66c9e95ea7476ffc3ee3d0a85e6b259527441" }.each do |platform, digest|
      get "/runner/v1/releases/0.1.0/#{platform}"

      assert_response :found
      assert_equal "https://github.com/AixleHQ/flow/releases/download/runner-v0.1.0/aixle-runner-#{platform}",
                   response.headers["Location"]
      assert_equal digest, response.headers["X-Aixle-Runner-Sha256"]
    end
    get "/runner/v1/releases/0.0.9/linux-amd64"
    assert_refused :not_found, "not_found"
  end

  # == the skew policy at register ==

  test "register refuses a runner below min_version with the upgrade message, and the token stays usable" do
    pin
    token = Runners::Credentials.mint_registration!(@runner)

    register(token, version: "1.1.9")

    assert_refused :bad_request, "runner_version_unsupported"
    assert_equal "aixle-runner 1.1.9 is no longer supported (minimum 1.2.0). Update aixle-runner.", response.parsed_body["message"]
    assert_equal 0, RunnerEnvironment.count
    register(token, version: "1.2.0")
    assert_response :created
    assert_equal "1.2.0", RunnerEnvironment.sole.runner_version
  end

  test "the minimum is checked after the token, so a dead token learns nothing" do
    pin

    register("arreg_not-a-token", version: "1.0.0")

    assert_refused :unauthorized, "invalid_token"
  end

  test "a runner version over 255 characters is invalid_registration whether or not it is below min_version" do
    token = Runners::Credentials.mint_registration!(@runner)
    # Strict SemVer, 256 characters, below 1.2.0.
    overlength = "1.0.0-#{'a' * 250}"
    assert_equal 256, overlength.length

    pin
    register(token, version: overlength)
    assert_refused :unprocessable_entity, "invalid_registration"

    pin("min_version" => nil)
    register(token, version: overlength)
    assert_refused :unprocessable_entity, "invalid_registration"

    assert_equal 0, RunnerEnvironment.count
    register(token, version: "1.2.0")
    assert_response :created
  end

  test "a machine registered before min_version was raised keeps polling" do
    pair = registered_pair
    pin("min_version" => "1.5.0")

    poll(pair)

    assert_response :ok
  end

  test "the protocol versions are the pinned ones, and the runner version must be strict SemVer" do
    token = Runners::Credentials.mint_registration!(@runner)

    register(token, headers: { "X-Aixle-Runner-Protocol" => "2" })
    assert_refused :bad_request, "unsupported_protocol"
    %w[01.2.3 1.2.3-01 1.2.3-..].each do |version|
      register(token, version: version)
      assert_refused :bad_request, "invalid_runner_version"
    end
    register(token, version: "1.5.0-rc.1+build.7")
    assert_response :created
  end

  # == auto_update at register ==

  test "a machine configured with --no-auto-update is recorded so, and one without the field updates itself" do
    pair = registered_pair(auto_update: false)
    environment = RunnerEnvironment.sole
    assert_not environment.auto_update

    register(Runners::Credentials.mint_registration!(@runner), REGISTRATION.merge(name: "build-02"))
    assert_response :created
    assert RunnerEnvironment.where.not(id: environment.id).sole.auto_update
    assert pair["access_token"].present?

    register(Runners::Credentials.mint_registration!(@runner), REGISTRATION.merge(auto_update: nil))
    assert_refused :unprocessable_entity, "invalid_registration"
    register(Runners::Credentials.mint_registration!(@runner), REGISTRATION.merge(auto_update: "no"))
    assert_refused :unprocessable_entity, "invalid_registration"
  end

  # == the update offer in GET /runner/v1/ops ==

  test "an idle machine below the recommended version gets the update in the empty answer" do
    pin
    pair = registered_pair

    poll(pair)

    assert_response :ok
    assert_equal({ "ops" => [],
                   "update" => { "version" => "1.5.0", "sha256" => AMD64 } },
                 response.parsed_body)
  end

  test "the offer follows the version the request reports, so an updated machine is not offered it again" do
    pin
    pair = registered_pair

    poll(pair, version: "1.5.0")

    assert_equal({ "ops" => [] }, response.parsed_body)
  end

  test "an answer with ops carries no update, and neither does one while the machine holds a session" do
    pin
    pair = registered_pair
    environment = RunnerEnvironment.sole
    session = create(:runner_session, :holding, environment: environment)
    operation = Runners::Operations.enqueue!(environment, op: "exec", payload: { "cmd" => "true" }, session: session,
                                                          deadline_at: 5.minutes.from_now.change(usec: 0))

    poll(pair)
    assert_equal [ operation.id ], response.parsed_body["ops"].pluck("id")
    assert_not response.parsed_body.key?("update")

    poll(pair, after: operation.sequence)
    assert_equal({ "ops" => [] }, response.parsed_body)

    environment.update!(current_session_id: nil)
    poll(pair, after: operation.sequence)
    assert_equal "1.5.0", response.parsed_body.dig("update", "version")
  end

  test "a session that takes the machine during the wait is seen when the wait ends" do
    pin
    pair = registered_pair
    environment = RunnerEnvironment.sole
    session = nil
    # Called as the poll's wait for a wake-up ends (Runners::Operations.poll).
    take_machine = ->(*) { session ||= create(:runner_session, :holding, environment: environment) }

    ActiveSupport::Notifications.subscribed(take_machine, "wait.runner_operations") { poll(pair, wait: 1) }

    assert_not_nil session

    assert_equal({ "ops" => [] }, response.parsed_body)
  end

  test "no update for a machine or a runner that opted out, or without a recommendation" do
    pin
    opted_out = registered_pair(auto_update: false)
    poll(opted_out)
    assert_equal({ "ops" => [] }, response.parsed_body)

    pair = registered_pair(name: "build-02")
    @runner.update!(config: { "auto_update" => false })
    poll(pair)
    assert_equal({ "ops" => [] }, response.parsed_body)

    @runner.update!(config: {})
    pin("recommended_version" => nil)
    poll(pair)
    assert_equal({ "ops" => [] }, response.parsed_body)
  end

  private

  def headers_for(token, version: "1.4.0", overrides: {})
    { "Authorization" => "Bearer #{token}", "X-Aixle-Runner-Protocol" => "1",
      "X-Aixle-Runner-Version" => version }.merge(overrides).compact
  end

  def register(token, body = REGISTRATION, version: "1.4.0", headers: {})
    post "/runner/v1/register", params: body, headers: headers_for(token, version: version, overrides: headers), as: :json
  end

  def registered_pair(name: "build-01", auto_update: nil)
    body = REGISTRATION.merge(name: name)
    body = body.merge(auto_update: auto_update) unless auto_update.nil?
    register(Runners::Credentials.mint_registration!(@runner), body)
    assert_response :created
    response.parsed_body
  end

  def poll(pair, after: 0, wait: 0, version: "1.4.0")
    get "/runner/v1/ops", params: { after: after, wait: wait }, headers: headers_for(pair["access_token"], version: version)
  end

  def assert_refused(status, error)
    assert_response status
    assert_equal error, response.parsed_body["error"]
  end
end
