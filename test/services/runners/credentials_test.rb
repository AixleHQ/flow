# frozen_string_literal: true

require "test_helper"

class Runners::CredentialsTest < ActiveSupport::TestCase
  setup do
    @runner = create(:runner, :manual)
    @environment = create(:runner_environment, runner: @runner)
  end

  test "a registration token is stored as its digest only and expires in an hour" do
    freeze_time
    token = Runners::Credentials.mint_registration!(@runner)

    credential = RunnerCredential.sole
    assert_equal "registration", credential.kind
    assert_equal RunnerCredential.digest(token), credential.token_digest
    assert_equal 1.hour.from_now, credential.expires_at
    assert_nil credential.runner_environment
    assert_not_includes credential.attributes.values.map(&:to_s), token
    assert_equal credential, Runners::Credentials.usable(token, kind: :registration)
  end

  test "registration tokens are minted for manual runners only" do
    error = assert_raises(ArgumentError) { Runners::Credentials.mint_registration!(create(:runner, :coder)) }
    assert_match(/manual/, error.message)
  end

  test "a registration token is unusable once used, revoked or expired" do
    used = Runners::Credentials.mint_registration!(@runner)
    RunnerCredential.find_by_token(used, kind: :registration).update!(used_at: Time.current, runner_environment: @environment)
    revoked = Runners::Credentials.mint_registration!(@runner)
    RunnerCredential.find_by_token(revoked, kind: :registration).update!(revoked_at: Time.current)
    expiring = Runners::Credentials.mint_registration!(@runner)

    assert_nil Runners::Credentials.usable(used, kind: :registration)
    assert_nil Runners::Credentials.usable(revoked, kind: :registration)
    travel 1.hour + 1.second
    assert_nil Runners::Credentials.usable(expiring, kind: :registration)
  end

  test "a token is usable only as its own kind" do
    pair = Runners::Credentials.issue_pair!(@environment)

    assert_nil Runners::Credentials.usable(pair.refresh_token, kind: :access)
    assert_nil Runners::Credentials.usable(pair.access_token, kind: :registration)
    assert_nil Runners::Credentials.usable("", kind: :access)
    assert Runners::Credentials.usable(pair.access_token, kind: :access)
  end

  test "a pair is an hour-long access token and a 30-day refresh token of one family" do
    freeze_time
    pair = Runners::Credentials.issue_pair!(@environment)

    access = RunnerCredential.find_by_token(pair.access_token, kind: :access)
    refresh = RunnerCredential.find_by_token(pair.refresh_token, kind: :refresh)
    assert_equal 1.hour.from_now, access.expires_at
    assert_equal 30.days.from_now, refresh.expires_at
    assert_equal access.family_id, refresh.family_id
    assert_equal [ @environment ] * 2, [ access.runner_environment, refresh.runner_environment ]
    assert_equal [ access.expires_at, refresh.expires_at ], [ pair.access_token_expires_at, pair.refresh_token_expires_at ]
  end

  test "a refresh rotates into a new pair of the same family and is spent" do
    first = Runners::Credentials.issue_pair!(@environment)
    refresh = RunnerCredential.find_by_token(first.refresh_token, kind: :refresh)

    second = Runners::Credentials.rotate!(refresh)

    assert refresh.reload.used?
    assert_not_equal first.refresh_token, second.refresh_token
    assert_equal refresh.family_id, RunnerCredential.find_by_token(second.refresh_token, kind: :refresh).family_id
    assert Runners::Credentials.usable(second.access_token, kind: :access)
  end

  test "reusing a spent refresh token revokes the whole family and says so on the environment" do
    first = Runners::Credentials.issue_pair!(@environment)
    old_refresh = RunnerCredential.find_by_token(first.refresh_token, kind: :refresh)
    second = Runners::Credentials.rotate!(old_refresh)
    other_machine = Runners::Credentials.issue_pair!(create(:runner_environment, runner: @runner))

    error = assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(old_refresh.reload) }

    assert_equal "credential_reuse_detected", error.reason
    assert_equal "credential reuse detected", @environment.reload.state_reason
    assert RunnerCredential.where(family_id: old_refresh.family_id).all?(&:revoked?)
    assert_nil Runners::Credentials.usable(second.access_token, kind: :access)
    assert Runners::Credentials.usable(other_machine.access_token, kind: :access)
  end

  test "a refresh token unused for 30 days, or revoked, rotates into nothing" do
    expiring = RunnerCredential.find_by_token(Runners::Credentials.issue_pair!(@environment).refresh_token, kind: :refresh)
    revoked = RunnerCredential.find_by_token(Runners::Credentials.issue_pair!(@environment).refresh_token, kind: :refresh)
    revoked.update!(revoked_at: Time.current)

    assert_equal "invalid_token", assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(revoked) }.reason
    travel 30.days + 1.second
    assert_equal "invalid_token", assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(expiring) }.reason
    assert_not expiring.reload.used?
  end
end
