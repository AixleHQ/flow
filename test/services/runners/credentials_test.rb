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

  test "a revoked or deleted runner mints no registration token" do
    deleted = create(:runner, :manual, company: @runner.company)
    @runner.revoke!
    deleted.soft_delete!

    refusals = [ @runner, deleted ].map do |runner|
      assert_raises(Runners::Credentials::Refused) { Runners::Credentials.mint_registration!(runner) }
    end

    assert_equal %w[runner_revoked runner_revoked], refusals.map(&:reason)
    assert_empty RunnerCredential.where(kind: :registration)
  end

  test "a refresh token is refreshable unless revoked, of a gone environment, or expired unspent" do
    spent = Runners::Credentials.issue_pair!(@environment).refresh_token
    Runners::Credentials.rotate!(RunnerCredential.find_by_token(spent, kind: :refresh))
    expiring = Runners::Credentials.issue_pair!(@environment).refresh_token
    travel 30.days + 1.second
    live = Runners::Credentials.issue_pair!(@environment)
    revoked = Runners::Credentials.issue_pair!(@environment).refresh_token
    RunnerCredential.find_by_token(revoked, kind: :refresh).update!(revoked_at: Time.current)
    gone_environment = create(:runner_environment, runner: @runner)
    gone = Runners::Credentials.issue_pair!(gone_environment).refresh_token
    gone_environment.update!(state: :gone)

    assert Runners::Credentials.refreshable(live.refresh_token)
    assert Runners::Credentials.refreshable(spent), "a spent token passes so that rotate! detects its reuse"
    assert_nil Runners::Credentials.refreshable(live.access_token)
    assert_nil Runners::Credentials.refreshable(expiring)
    assert_nil Runners::Credentials.refreshable(revoked)
    assert_nil Runners::Credentials.refreshable(gone)
    assert_nil Runners::Credentials.refreshable("arref_not-a-token")
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
    Runners::Credentials.record_use!(RunnerCredential.find_by_token(second.access_token, kind: :access))
    other_machine = Runners::Credentials.issue_pair!(create(:runner_environment, runner: @runner))

    error = assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(old_refresh.reload) }

    assert_equal "credential_reuse_detected", error.reason
    assert_equal "credential reuse detected", @environment.reload.state_reason
    assert RunnerCredential.where(family_id: old_refresh.family_id).all?(&:revoked?)
    assert_nil Runners::Credentials.usable(second.access_token, kind: :access)
    assert Runners::Credentials.usable(other_machine.access_token, kind: :access)
  end

  # == a retry after a lost response (§9.2) ==

  test "a spent refresh token presented again within the window, its pair unused, rotates as a retry" do
    first = refresh_credential(Runners::Credentials.issue_pair!(@environment))
    lost = Runners::Credentials.rotate!(first)
    spent_at = first.reload.used_at
    travel 30.seconds

    retried = Runners::Credentials.rotate!(first.reload)

    assert_nil Runners::Credentials.usable(lost.access_token, kind: :access)
    assert_nil Runners::Credentials.refreshable(lost.refresh_token)
    assert Runners::Credentials.usable(retried.access_token, kind: :access)
    fresh = refresh_credential(retried)
    assert_equal [ first.family_id, first.id ], [ fresh.family_id, fresh.rotated_from_id ]
    assert_equal spent_at, first.reload.used_at, "a retry does not extend the window"
    assert_nil @environment.reload.state_reason
    assert Runners::Credentials.rotate!(fresh), "the retried pair rotates in turn"
  end

  test "a second retry within the window revokes the first retry's pair, and the window counts from the spend" do
    first = refresh_credential(Runners::Credentials.issue_pair!(@environment))
    Runners::Credentials.rotate!(first)
    travel 20.seconds
    once = Runners::Credentials.rotate!(first.reload)
    travel 20.seconds

    twice = Runners::Credentials.rotate!(first.reload)

    assert_nil Runners::Credentials.usable(once.access_token, kind: :access)
    assert_nil Runners::Credentials.refreshable(once.refresh_token)
    assert Runners::Credentials.usable(twice.access_token, kind: :access)
    travel 21.seconds
    assert_reuse_detected first
    assert_nil Runners::Credentials.usable(twice.access_token, kind: :access)
  end

  test "a spent refresh token is reuse once the pair it issued was used, by its access or its refresh token" do
    used_access = refresh_credential(Runners::Credentials.issue_pair!(@environment))
    by_access = Runners::Credentials.rotate!(used_access)
    Runners::Credentials.record_use!(RunnerCredential.find_by_token(by_access.access_token, kind: :access))
    assert_reuse_detected used_access

    other = create(:runner_environment, runner: @runner)
    used_refresh = refresh_credential(Runners::Credentials.issue_pair!(other))
    Runners::Credentials.rotate!(refresh_credential(Runners::Credentials.rotate!(used_refresh)))
    assert_reuse_detected used_refresh.reload
  end

  test "a spent refresh token presented 61 seconds after the spend is reuse, its pair unused" do
    first = refresh_credential(Runners::Credentials.issue_pair!(@environment))
    lost = Runners::Credentials.rotate!(first)
    travel Runners::Credentials::RETRY_WINDOW + 1.second

    assert_reuse_detected first.reload
    assert_nil Runners::Credentials.usable(lost.access_token, kind: :access)
  end

  test "a refresh token two rotations old is reuse within the window" do
    first = refresh_credential(Runners::Credentials.issue_pair!(@environment))
    second = refresh_credential(Runners::Credentials.rotate!(first))
    newest = Runners::Credentials.rotate!(second)

    assert_reuse_detected first.reload
    assert_nil Runners::Credentials.usable(newest.access_token, kind: :access)
  end

  test "a spent refresh token of a revoked runner or a gone environment is refused within the window, as before" do
    revoked = refresh_credential(Runners::Credentials.issue_pair!(@environment))
    Runners::Credentials.rotate!(revoked)
    @runner.revoke!
    gone_environment = create(:runner_environment, runner: create(:runner, :manual, company: @runner.company))
    gone = refresh_credential(Runners::Credentials.issue_pair!(gone_environment))
    Runners::Credentials.rotate!(gone)
    gone_environment.update!(state: :gone)

    assert_equal "runner_revoked", assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(revoked.reload) }.reason
    assert_equal "invalid_token", assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(gone.reload) }.reason
    assert_equal 4, RunnerCredential.where(runner_environment: gone_environment).count, "no pair is issued"
    assert_nil gone_environment.reload.state_reason
  end

  test "recording an access token's use writes it once" do
    access = RunnerCredential.find_by_token(Runners::Credentials.issue_pair!(@environment).access_token, kind: :access)
    freeze_time

    Runners::Credentials.record_use!(access)
    travel 1.minute
    Runners::Credentials.record_use!(RunnerCredential.find(access.id))

    assert_equal 1.minute.ago, access.reload.used_at
  end

  test "a spent refresh token replayed after its own expiry still revokes the live family" do
    first = RunnerCredential.find_by_token(Runners::Credentials.issue_pair!(@environment).refresh_token, kind: :refresh)
    second = RunnerCredential.find_by_token(Runners::Credentials.rotate!(first).refresh_token, kind: :refresh)
    travel 29.days
    newest = Runners::Credentials.rotate!(second)
    travel 2.days

    error = assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(first.reload) }

    assert_equal "credential_reuse_detected", error.reason
    assert_equal "credential reuse detected", @environment.reload.state_reason
    assert RunnerCredential.find_by_token(newest.refresh_token, kind: :refresh).revoked?
    assert_empty RunnerCredential.where(family_id: first.family_id).unrevoked
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

  test "credentials of a gone environment are refused even when their rows are not revoked" do
    pair = Runners::Credentials.issue_pair!(@environment)
    refresh = RunnerCredential.find_by_token(pair.refresh_token, kind: :refresh)
    @environment.update!(state: :gone)

    assert_nil Runners::Credentials.usable(pair.access_token, kind: :access)
    assert_equal "invalid_token", assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(refresh) }.reason
    assert_not refresh.reload.used?
    assert_equal 2, RunnerCredential.where(runner_environment: @environment).unrevoked.count
  end

  test "revoking or deleting a runner revokes every credential it has, and only its own" do
    pair = Runners::Credentials.issue_pair!(@environment)
    registration = Runners::Credentials.mint_registration!(@runner)
    deleted = create(:runner, :manual, company: @runner.company)
    deleted_registration = Runners::Credentials.mint_registration!(deleted)
    other = Runners::Credentials.issue_pair!(create(:runner_environment, runner: create(:runner, :manual)))

    @runner.revoke!
    deleted.soft_delete!

    assert_empty @runner.credentials.unrevoked
    assert_empty deleted.credentials.unrevoked
    assert_nil Runners::Credentials.usable(pair.access_token, kind: :access)
    assert_nil Runners::Credentials.usable(registration, kind: :registration)
    assert_nil Runners::Credentials.usable(deleted_registration, kind: :registration)
    assert Runners::Credentials.usable(other.access_token, kind: :access)
  end

  test "a revoked runner issues no pair, by rotation or by registration" do
    refresh = RunnerCredential.find_by_token(Runners::Credentials.issue_pair!(@environment).refresh_token, kind: :refresh)
    registration = RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration)
    @runner.revoke!

    rotation = assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(refresh) }
    registering = assert_raises(Runners::Credentials::Refused) do
      Runners::Registration.register!(registration, name: "build-01", os: "linux", arch: "amd64", facts: {},
                                                    ephemeral: false, runner_version: "1.4.0", protocol_version: "1")
    end

    assert_equal %w[runner_revoked runner_revoked], [ rotation.reason, registering.reason ]
    assert_equal 1, RunnerEnvironment.count
  end

  private

  def refresh_credential(pair)
    RunnerCredential.find_by_token(pair.refresh_token, kind: :refresh)
  end

  def assert_reuse_detected(credential)
    error = assert_raises(Runners::Credentials::Refused) { Runners::Credentials.rotate!(credential) }
    assert_equal "credential_reuse_detected", error.reason
    assert_equal "credential reuse detected", credential.runner_environment.reload.state_reason
    assert_empty RunnerCredential.where(family_id: credential.family_id).unrevoked
  end
end
