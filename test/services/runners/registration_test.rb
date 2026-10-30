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
    ephemeral = assert_raises(Runners::Credentials::Refused) { register(ephemeral: true) }
    invalid = assert_raises(Runners::Credentials::Refused) { register(name: "") }

    assert_equal "ephemeral_not_supported", ephemeral.reason
    assert_equal "invalid_registration", invalid.reason
    assert_match(/Display name/, invalid.message)
    assert_not @credential.reload.used?
    assert_equal 0, RunnerEnvironment.count
  end

  test "unregistering marks the environment gone and revokes its credentials only" do
    environment = register.environment
    other = Runners::Registration.register!(
      RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration),
      name: "build-02", os: "linux", arch: "arm64", facts: {}, ephemeral: false,
      runner_version: "1.4.0", protocol_version: "1"
    )

    Runners::Registration.unregister!(environment)

    assert environment.reload.gone?
    assert environment.credentials.all?(&:revoked?)
    assert other.environment.reload.registered?
    assert other.environment.credentials.none?(&:revoked?)
  end

  private

  def register(name: "build-01", ephemeral: false)
    Runners::Registration.register!(@credential, name: name, os: "linux", arch: "amd64", facts: { "docker" => "27.1.0" },
                                                 ephemeral: ephemeral, runner_version: "1.4.0", protocol_version: "1")
  end
end
