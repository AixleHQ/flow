# frozen_string_literal: true

require "test_helper"

# A runner's revocation and the issuance of a pair race on separate database
# connections (docs/design/agent-runtimes/DESIGN.md §9.3). Whichever takes the
# runner's row first, no unrevoked credential of the runner survives: an
# issuance that holds the row has its pair revoked once the revocation gets the
# row, and one that waits for it is refused. Each race is forced into its order
# by holding one side's transaction open until the other is seen waiting on a
# lock. An unregister races a revocation the same way, since both revoke the
# same credential rows. The racing work commits on its own connections, so this
# test opts out of the transactional wrapper and cleans up after itself.
class Runners::RevocationConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  LOCK_WAIT_TIMEOUT = 10 # seconds

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @runner = create(:runner, :manual, company: @company, created_by: @user)
  end

  teardown do
    # Its environments and credentials go with it, by ON DELETE CASCADE.
    Runner.where(id: @runner.id).delete_all
    @user.company_memberships.delete_all
    UserIdentity.where(user_id: @user.id).delete_all
    UserSession.where(user_id: @user.id).delete_all
    @user.delete
    CompanyAuthPolicy.where(company_id: @company.id).delete_all
    IdentityProvider.where(company_id: @company.id).delete_all
    @company.delete
  end

  test "a revocation that waits on a refresh rotation revokes the pair it issued" do
    environment = create(:runner_environment, runner: @runner)
    refresh = refresh_credential(Runners::Credentials.issue_pair!(environment))

    issued = issue_then_revoke { Runners::Credentials.rotate!(RunnerCredential.find(refresh.id)) }

    assert RunnerCredential.find_by_token(issued.access_token, kind: :access).revoked?
    assert_empty RunnerCredential.where(runner_id: @runner.id).unrevoked
  end

  test "a revocation that waits on a registration revokes the pair it issued" do
    registration = RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration)

    issued = issue_then_revoke { register(RunnerCredential.find(registration.id)).pair }

    assert RunnerCredential.find_by_token(issued.refresh_token, kind: :refresh).revoked?
    assert_empty RunnerCredential.where(runner_id: @runner.id).unrevoked
  end

  test "a rotation and a registration that wait on a revocation are refused" do
    environment = create(:runner_environment, runner: @runner)
    refresh = refresh_credential(Runners::Credentials.issue_pair!(environment))
    registration = RunnerCredential.find_by_token(Runners::Credentials.mint_registration!(@runner), kind: :registration)

    refusals = revoke_then_issue(
      -> { Runners::Credentials.rotate!(RunnerCredential.find(refresh.id)) },
      -> { register(RunnerCredential.find(registration.id)) }
    )

    assert refusals.all?(Runners::Credentials::Refused), refusals.inspect
    assert_equal 1, RunnerEnvironment.where(runner_id: @runner.id).count
    assert_empty RunnerCredential.where(runner_id: @runner.id).unrevoked
  end

  test "a revocation that waits on an unregister finds the machine gone and its credentials revoked" do
    environment = create(:runner_environment, runner: @runner)
    Runners::Credentials.issue_pair!(environment)

    issue_then_revoke { Runners::Registration.unregister!(RunnerEnvironment.find(environment.id)) }

    assert environment.reload.gone?
    assert @runner.reload.revoked?
    assert_empty RunnerCredential.where(runner_id: @runner.id).unrevoked
  end

  test "an unregister that waits on a revocation is refused" do
    environment = create(:runner_environment, runner: @runner)
    Runners::Credentials.issue_pair!(environment)

    refusals = revoke_then_issue(-> { Runners::Registration.unregister!(RunnerEnvironment.find(environment.id)) })

    assert_equal [ "runner_revoked" ], refusals.map(&:reason)
    assert environment.reload.registered?
    assert_empty RunnerCredential.where(runner_id: @runner.id).unrevoked
  end

  private

  # The issuance commits only once the revocation is waiting on a lock.
  def issue_then_revoke(&issue)
    issued = Queue.new
    release = Queue.new
    issuer = Thread.new do
      on_own_connection do
        ActiveRecord::Base.transaction do
          pair = issue.call
          issued << true
          release.pop
          pair
        end
      end
    end
    issued.pop(timeout: LOCK_WAIT_TIMEOUT) || flunk("the issuance never finished")
    revoker_pid = Queue.new
    revoker = Thread.new do
      on_own_connection do
        revoker_pid << backend_pid
        Runner.find(@runner.id).revoke!
      end
    end
    wait_until_waiting_on_lock(revoker_pid.pop(timeout: LOCK_WAIT_TIMEOUT))
    release << true
    revoker.value
    issuer.value
  ensure
    release << true
    [ issuer, revoker ].compact.each(&:join)
  end

  # The revocation commits only once every issuer is waiting on a lock.
  def revoke_then_issue(*issues)
    revoked = Queue.new
    release = Queue.new
    revoker = Thread.new do
      on_own_connection do
        ActiveRecord::Base.transaction do
          Runner.find(@runner.id).revoke!
          revoked << true
          release.pop
        end
      end
    end
    revoked.pop(timeout: LOCK_WAIT_TIMEOUT) || flunk("the revocation never finished")
    pids = Queue.new
    issuers = issues.map do |issue|
      Thread.new do
        on_own_connection do
          pids << backend_pid
          issue.call
        rescue Runners::Credentials::Refused => refusal
          refusal
        end
      end
    end
    issues.size.times { wait_until_waiting_on_lock(pids.pop(timeout: LOCK_WAIT_TIMEOUT)) }
    release << true
    revoker.value
    issuers.map(&:value)
  ensure
    release << true
    [ revoker, *issuers ].compact.each(&:join)
  end

  def on_own_connection(&)
    ActiveRecord::Base.connection_pool.with_connection(&)
  end

  def backend_pid
    ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
  end

  # Uncached: the test runs inside the executor, whose query cache would answer
  # every poll with the first one's result.
  def wait_until_waiting_on_lock(pid)
    deadline = Time.current + LOCK_WAIT_TIMEOUT
    query = "SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}"
    until ActiveRecord::Base.uncached { ActiveRecord::Base.connection.select_value(query) } == "Lock"
      flunk "backend #{pid} never waited on a lock" if Time.current > deadline
      sleep 0.01
    end
  end

  def refresh_credential(pair)
    RunnerCredential.find_by_token(pair.refresh_token, kind: :refresh)
  end

  def register(credential)
    Runners::Registration.register!(credential, name: "build-01", os: "linux", arch: "amd64", facts: {},
                                                ephemeral: false, runner_version: "1.4.0", protocol_version: "1")
  end
end
