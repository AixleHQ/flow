# frozen_string_literal: true

require "test_helper"

class Runners::RegistrationTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
    @token = Runners::Credentials.mint_registration!(@runner)
    @credential = RunnerCredential.find_by_token(@token, kind: :registration)
  end

  test "a registration creates one registered environment and spends the token on it" do
    result = register

    environment = result.environment
    assert_equal [ @runner, @runner.company ], [ environment.runner, environment.company ]
    assert_equal %w[registered registered], [ environment.origin, environment.state ]
    assert_equal [ "build-01", "linux", "amd64" ], [ environment.display_name, environment.os, environment.arch ]
    assert_equal({ "docker" => "27.1.0" }, environment.facts)
    assert_equal [ "1.4.0", "1" ], [ environment.runner_version, environment.protocol_version ]
    assert_equal false, environment.ephemeral # rubocop:disable Minitest/RefuteFalse
    assert_match(/\Aaixle-r#{@runner.id}-\h{8}\z/, environment.key)
    assert @credential.reload.used?
    assert_equal environment, @credential.runner_environment
    assert Runners::Credentials.usable(result.pair.access_token, kind: :access)
  end

  test "a token registers one machine only" do
    register

    error = assert_raises(Runners::Credentials::Refused) { register }
    assert_equal "invalid_token", error.reason
    assert_equal 1, RunnerEnvironment.count
  end

  test "an ephemeral or invalid registration is refused and leaves the token unspent" do
    ephemeral = assert_raises(Runners::Credentials::Refused) { register({ "ephemeral" => true }) }
    invalid = assert_raises(Runners::Credentials::Refused) { register({ "name" => "" }) }

    assert_equal "ephemeral_not_supported", ephemeral.reason
    assert_equal "invalid_registration", invalid.reason
    assert_match(/Display name/, invalid.message)
    assert_not @credential.reload.used?
    assert_equal 0, RunnerEnvironment.count
  end

  # PROTOCOL.md §5.1: the version refusals, then `ephemeral`, then the schema.
  test "the refusals come in the protocol's order and leave the token unspent" do
    Runners::Release.stubs(:pins).returns(Runners::Release.parse(
      "protocol_supported" => [ 1 ], "min_version" => "1.2.0", "recommended_version" => nil, "binaries" => {},
      "download_url" => "https://github.com/AixleHQ/flow/releases/download/runner-v%{version}/aixle-runner-%{platform}"
    ))
    invalid_body = { "name" => 7, "ephemeral" => true }

    too_long = assert_raises(Runners::Credentials::Refused) { register(invalid_body, runner_version: "1.0.0+#{'a' * 250}") }
    below = assert_raises(Runners::Credentials::Refused) { register(invalid_body, runner_version: "1.1.0") }
    ephemeral = assert_raises(Runners::Credentials::Refused) { register(invalid_body) }
    schema = assert_raises(Runners::Credentials::Refused) { register({ "name" => 7 }) }

    assert_equal [ "invalid_registration", "X-Aixle-Runner-Version must be at most 255 characters." ],
                 [ too_long.reason, too_long.message ]
    assert_equal [ "runner_version_unsupported",
                   "aixle-runner 1.1.0 is no longer supported (minimum 1.2.0). Update aixle-runner." ],
                 [ below.reason, below.message ]
    assert_equal "ephemeral_not_supported", ephemeral.reason
    assert_equal "invalid_registration", schema.reason
    assert_match(/`name` is required and must be a string/, schema.message)
    assert_not @credential.reload.used?
    assert_equal 0, RunnerEnvironment.count
  end

  test "a body that fails the schema is refused" do
    [ { "name" => nil }, { "facts" => nil }, { "facts" => [] }, { "auto_update" => nil }, { "auto_update" => "no" },
      { "os" => "x" * 256 }, { "arch" => "x" * 256 } ].each do |change|
      error = assert_raises(Runners::Credentials::Refused, change.inspect) { register(change) }
      assert_equal "invalid_registration", error.reason, change.inspect
    end
    missing = assert_raises(Runners::Credentials::Refused) do
      Runners::Registration.register!(@credential, {}, runner_version: "1.4.0", protocol_version: "1")
    end
    assert_equal "invalid_registration", missing.reason
    assert_equal 0, RunnerEnvironment.count
  end

  test "the body is normalized: the name stripped, an os or arch that is not a string ignored, facts and auto_update defaulted" do
    environment = Runners::Registration.register!(@credential, { "name" => "  build-01 ", "os" => 7, "arch" => [ "amd64" ] },
                                                  runner_version: "1.4.0", protocol_version: "1").environment

    assert_equal [ "build-01", nil, nil ], [ environment.display_name, environment.os, environment.arch ]
    assert_equal({}, environment.facts)
    assert environment.auto_update
  end

  test "auto_update false is recorded, and symbol keys are read like the request's string keys" do
    environment = Runners::Registration.register!(@credential, { name: "build-01", auto_update: false },
                                                  runner_version: "1.4.0", protocol_version: "1").environment

    assert_equal "build-01", environment.display_name
    assert_not environment.auto_update
  end

  test "unregistering marks the environment gone and revokes its credentials only" do
    environment = register.environment
    other = Runners::Registration.register!(
      RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration),
      { "name" => "build-02", "os" => "linux", "arch" => "arm64", "facts" => {}, "ephemeral" => false },
      runner_version: "1.4.0", protocol_version: "1"
    )

    Runners::Registration.unregister!(environment)

    assert environment.reload.gone?
    assert environment.credentials.all?(&:revoked?)
    assert other.environment.reload.registered?
    assert other.environment.credentials.none?(&:revoked?)
  end

  private

  def register(changes = {}, runner_version: "1.4.0")
    body = { "name" => "build-01", "os" => "linux", "arch" => "amd64", "facts" => { "docker" => "27.1.0" },
             "ephemeral" => false }.merge(changes)
    Runners::Registration.register!(@credential, body, runner_version: runner_version, protocol_version: "1")
  end
end
