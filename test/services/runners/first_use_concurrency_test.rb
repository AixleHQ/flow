# frozen_string_literal: true

require "test_helper"

# An access token's first use and a retry of the refresh that issued it race on
# separate database connections (docs/design/agent-runtimes/DESIGN.md §9.2).
# Both take the access token's row lock, so whichever takes it first decides:
# a retry that revokes the pair first leaves the first use unrecorded, and the
# gateway refuses the request; a first use that commits first makes the retry
# reuse. Each race is forced into its order by holding one side's transaction
# open until the other is seen waiting on a lock, as in
# revocation_concurrency_test.rb. The racing work commits on its own
# connections, so this test opts out of the transactional wrapper and cleans
# up after itself.
class Runners::FirstUseConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  LOCK_WAIT_TIMEOUT = 10 # seconds

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @runner = create(:runner, :manual, company: @company, created_by: @user)
    @environment = create(:runner_environment, runner: @runner)
    @spent = RunnerCredential.find_by_token(Runners::Credentials.issue_pair!(@environment).refresh_token, kind: :refresh)
    @lost = Runners::Credentials.rotate!(@spent)
    @lost_access = RunnerCredential.find_by_token(@lost.access_token, kind: :access)
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

  test "a retry that revokes the issued pair first leaves its access token's first use refused" do
    retried, recorded = hold_then(
      -> { Runners::Credentials.rotate!(RunnerCredential.find(@spent.id)) },
      -> { Runners::Credentials.record_use!(@lost_access) }
    )

    assert_not recorded
    assert_nil @lost_access.reload.used_at
    assert @lost_access.revoked?
    assert Runners::Credentials.usable(retried.access_token, kind: :access)
    assert_nil @environment.reload.state_reason
  end

  test "a first use that commits first makes the retry reuse" do
    recorded, refusal = hold_then(
      -> { Runners::Credentials.record_use!(@lost_access) },
      -> { Runners::Credentials.rotate!(RunnerCredential.find(@spent.id)) }
    )

    assert recorded
    assert_equal "credential_reuse_detected", refusal.reason
    assert_equal Runners::Credentials::REUSE_DETECTED, @environment.reload.state_reason
    assert_empty RunnerCredential.where(family_id: @spent.family_id).unrevoked
  end

  private

  # Runs `first` in a transaction on its own connection and commits it only
  # once `second`, on another connection, is waiting on a lock. Returns both
  # results; a refusal is returned, not raised.
  def hold_then(first, second)
    done = Queue.new
    release = Queue.new
    holder = Thread.new do
      on_own_connection do
        ActiveRecord::Base.transaction do
          result = first.call
          done << true
          release.pop
          result
        end
      end
    end
    done.pop(timeout: LOCK_WAIT_TIMEOUT) || flunk("the first side never finished")
    pid = Queue.new
    waiter = Thread.new do
      on_own_connection do
        pid << backend_pid
        second.call
      rescue Runners::Credentials::Refused => refusal
        refusal
      end
    end
    wait_until_waiting_on_lock(pid.pop(timeout: LOCK_WAIT_TIMEOUT))
    release << true
    [ holder.value, waiter.value ]
  ensure
    release << true
    [ holder, waiter ].compact.each(&:join)
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
end
