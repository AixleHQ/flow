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
    assert_match(/\Aaixle-r#{@runner.id}-\h{8}\z/, environment.key)
    assert @credential.reload.used?
    assert_equal environment, @credential.runner_environment
    assert Runners::Credentials.usable(result.pair.access_token, kind: :access)
  end

  test "the machine records the address it registered from and the user who minted its token" do
    user = create(:user)
    token = Runners::Credentials.mint_registration!(@runner, created_by: user)
    credential = RunnerCredential.find_by_token(token, kind: :registration)

    environment = register(credential: credential, remote_ip: "203.0.113.7").environment

    assert_equal [ "203.0.113.7", user ], [ environment.first_seen_ip, environment.created_by ]
  end

  test "a machine registered with neither shows neither" do
    environment = register.environment

    assert_nil environment.first_seen_ip
    assert_nil environment.created_by
  end

  test "a token registers one machine only" do
    register

    error = assert_raises(Runners::Credentials::Refused) { register }
    assert_equal "invalid_token", error.reason
    assert_equal 1, RunnerEnvironment.count
  end

  test "an invalid registration is refused and leaves the token unspent" do
    blank = assert_raises(Runners::Credentials::Refused) { register(name: "   ") }
    too_long = assert_raises(Runners::Credentials::Refused) { register(os: "o" * 256) }

    assert_equal [ "invalid_registration", "invalid_registration" ], [ blank.reason, too_long.reason ]
    assert_match(/Display name/, blank.message)
    assert_not @credential.reload.used?
    assert_equal 0, RunnerEnvironment.count
  end

  test "the name is stored without its surrounding spaces, and auto_update false is recorded" do
    environment = register(name: "  build-01 ", os: nil, arch: nil, facts: {}, auto_update: false).environment

    assert_equal [ "build-01", nil, nil ], [ environment.display_name, environment.os, environment.arch ]
    assert_equal({}, environment.facts)
    assert_not environment.auto_update
  end

  test "unregistering marks the environment gone and revokes its credentials only" do
    environment = register.environment
    other = Runners::Registration.register!(
      RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration),
      name: "build-02", os: "linux", arch: "arm64", facts: {}, auto_update: true,
      runner_version: "1.4.0", protocol_version: "1"
    )

    Runners::Registration.unregister!(environment)

    assert environment.reload.gone?
    assert environment.credentials.all?(&:revoked?)
    assert other.environment.reload.registered?
    assert other.environment.credentials.none?(&:revoked?)
  end

  test "a machine that unregistered itself and one that was revoked say which in state_reason" do
    left = register.environment
    revoked = Runners::Registration.register!(
      RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration),
      name: "build-02", os: "linux", arch: "arm64", facts: {}, auto_update: true,
      runner_version: "1.4.0", protocol_version: "1"
    ).environment

    Runners::Registration.unregister!(left)
    assert Runners::Registration.revoke!(revoked)

    assert_equal "unregistered", left.reload.state_reason
    assert_equal "revoked", revoked.reload.state_reason
    assert_equal %w[gone gone], [ left.display_state, revoked.display_state ]

    Runners::Registration.unregister!(revoked)
    assert_equal "revoked", revoked.reload.state_reason, "a second unregister keeps how the machine left"
  end

  # == registering into a row the platform created (runner-coder.md §8.4) ==

  def bound_credential(environment)
    RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(environment.runner, environment: environment),
                                   kind: :registration)
  end

  def allocated(**attributes) = create(:runner_environment, :allocated, external_id: "ws-1", **attributes)

  test "a bound token fills the row the platform made, records what the machine reports, and moves it to booting" do
    environment = allocated
    credential = bound_credential(environment)

    result = register(credential: credential, name: "  ws-1 ", remote_ip: "203.0.113.9", auto_update: false)

    assert_equal environment, result.environment, "no second row"
    assert_equal 1, RunnerEnvironment.count
    environment.reload
    assert_equal "booting", environment.state
    assert_equal [ "ws-1", "linux", "amd64", "203.0.113.9" ], [ environment.display_name, environment.os, environment.arch, environment.first_seen_ip ]
    assert_equal({ "docker" => "27.1.0" }, environment.facts)
    assert_equal [ "1.4.0", "1", false ], [ environment.runner_version, environment.protocol_version, environment.auto_update ]
    assert_equal "allocated", environment.origin
    assert credential.reload.used?
    assert Runners::Credentials.usable(result.pair.access_token, kind: :access)
  end

  test "a row that is booting already is filled as well, and stays booting" do
    environment = allocated
    credential = bound_credential(environment)
    environment.update_columns(state: "booting")

    register(credential: credential)

    assert_equal "booting", environment.reload.state
  end

  test "a row that is gone, failed, torn down or already idle is refused, and the token is not spent" do
    %w[gone failed tearing_down idle].each do |state|
      environment = allocated
      credential = bound_credential(environment)
      environment.update_columns(state: state)

      error = assert_raises(Runners::Credentials::Refused, state) { register(credential: credential) }

      assert_equal "invalid_token", error.reason, state
      assert_not credential.reload.used?, state
    end
  end

  test "an invalid registration into a row leaves the token unspent and the row as it was" do
    environment = allocated
    credential = bound_credential(environment)

    blank = assert_raises(Runners::Credentials::Refused) { register(credential: credential, name: " ") }
    long = assert_raises(Runners::Credentials::Refused) { register(credential: credential, os: "o" * 256) }

    assert_equal %w[invalid_registration invalid_registration], [ blank.reason, long.reason ]
    assert_not credential.reload.used?
    assert_equal [ "provisioning", nil ], [ environment.reload.state, environment.display_name ]
  end

  test "a bound token is spent once: a second registration with it is refused and issues no second pair" do
    environment = allocated
    credential = bound_credential(environment)

    register(credential: RunnerCredential.find(credential.id))
    error = assert_raises(Runners::Credentials::Refused) { register(credential: RunnerCredential.find(credential.id)) }

    assert_equal "invalid_token", error.reason
    assert_equal 1, RunnerCredential.where(runner_environment: environment, kind: "access").count
  end

  # == ending an environment's registration, through its adapter (§6.1) ==

  test "a revoke of a machine of a retired runner finds it gone already, with no runner_revoked refusal" do
    environment = register.environment
    @runner.revoke!

    assert_not Runners::Registration.revoke!(environment.reload), "the runner's revoke already ended it"
    assert_equal "revoked", environment.state_reason
    assert environment.gone?
  end

  test "a per-environment Revoke of a manual machine fails the session it holds with the machine's message, and releases it" do
    environment = register.environment
    session = create(:runner_session, environment: environment, runner_environment: nil)
    Runners::Allocator.acquire!(session)

    assert Runners::Registration.revoke!(environment)

    assert environment.reload.gone?
    assert_nil environment.current_session_id
    assert_equal "failed", session.reload.state
    assert_equal "Machine \"build-01\" of runner \"#{@runner.name}\" was revoked.", session.error_message
  end

  test "a per-environment Revoke of an allocated environment ends its credentials and its live session, and tears it down" do
    adapter = with_fake_provisioned_adapter
    environment = allocated(state: "idle", last_heartbeat_at: Time.current)
    pair = Runners::Credentials.issue_pair!(environment)
    session = create(:runner_session, environment: environment, runner_environment: nil)
    Runners::Allocator.acquire!(session)

    assert Runners::Registration.revoke!(environment)

    assert_equal "gone", environment.reload.state, "torn down by its adapter"
    assert_nil Runners::Credentials.usable(pair.access_token, kind: :access)
    assert environment.credentials.all?(&:revoked?)
    assert_equal "failed", session.reload.state
    assert_equal "Machine \"#{environment.key}\" of runner \"#{environment.runner.name}\" was revoked.", session.error_message
    assert_includes adapter.calls, [ :end_registration, environment.id, "revoked" ]
  end

  test "a runner's Revoke ends every machine of a manual runner without a runner_revoked refusal, and a live session with the runner's message" do
    first = register.environment
    second = Runners::Registration.register!(
      RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration),
      name: "build-02", os: "linux", arch: "arm64", facts: {}, auto_update: true, runner_version: "1.4.0", protocol_version: "1"
    ).environment
    session = create(:runner_session, environment: first, runner_environment: nil)
    Runners::Allocator.acquire!(session)

    @runner.revoke!

    assert_equal %w[gone gone], [ first, second ].map { |machine| machine.reload.state }
    assert_equal %w[revoked revoked], [ first, second ].map(&:state_reason)
    assert_equal "failed", session.reload.state
    assert_equal "Runner \"#{@runner.name}\" was revoked, so the session running on it ended.", session.error_message
    assert_empty RunnerCredential.where(runner: @runner).unrevoked
  end

  test "a runner's Revoke ends the environments of a provisioned runner too, and a gone workspace is left alone" do
    with_fake_provisioned_adapter
    coder = create(:runner, :coder)
    live = create(:runner_environment, :allocated, runner: coder, state: "idle", last_heartbeat_at: Time.current)
    session = create(:runner_session, environment: live, runner_environment: nil)
    Runners::Allocator.acquire!(session)
    gone = create(:runner_environment, :allocated, runner: coder, state: "gone")

    coder.revoke!

    assert_equal "gone", live.reload.state
    assert_equal "failed", session.reload.state
    assert_equal "gone", gone.reload.state
  end

  private

  def register(credential: @credential, **changes)
    Runners::Registration.register!(
      credential,
      **{ name: "build-01", os: "linux", arch: "amd64", facts: { "docker" => "27.1.0" },
          auto_update: true, runner_version: "1.4.0", protocol_version: "1" }.merge(changes)
    )
  end
end
