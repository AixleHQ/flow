# frozen_string_literal: true

require "test_helper"

# A poll's delivery and an op's result race on separate database connections
# (docs/design/agent-runtimes/DESIGN.md §2.3, §6.4). Both lock the op's row, so
# they run in a defined order: a result that holds the row first is never
# returned by the delivery that waits on it, and a result that waits on a
# delivery is recorded once the delivery commits. Each race is forced into its
# order by holding one side's transaction open until the other is seen waiting
# on a lock. The racing work commits on its own connections, so this test opts
# out of the transactional wrapper and cleans up after itself.
class Runners::OperationsConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  LOCK_WAIT_TIMEOUT = 10 # seconds

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @runner = create(:runner, :manual, company: @company, created_by: @user)
    @environment = create(:runner_environment, runner: @runner)
  end

  teardown do
    # Its environments, credentials and operations go with it, by ON DELETE CASCADE.
    Runner.where(id: @runner.id).delete_all
    @user.company_memberships.delete_all
    UserIdentity.where(user_id: @user.id).delete_all
    UserSession.where(user_id: @user.id).delete_all
    @user.delete
    CompanyAuthPolicy.where(company_id: @company.id).delete_all
    IdentityProvider.where(company_id: @company.id).delete_all
    @company.delete
  end

  test "a result that wins the race is not delivered, and its op keeps its result" do
    operation = enqueue

    delivered = first_then_second(
      -> { Runners::Operations.record_result!(RunnerOperation.find(operation.id), status: "ok", result: { "exit_code" => 0 }) },
      -> { Runners::Operations.deliver!(@environment.id, after: 0) }
    )

    assert_empty delivered
    operation.reload
    assert operation.completed?
    assert_nil operation.delivered_at
    assert_nil operation.encrypted_payload
  end

  test "a result that waits on a delivery is recorded once the delivery commits" do
    operation = enqueue

    first_then_second(
      -> { Runners::Operations.deliver!(@environment.id, after: 0).tap { |ops| assert_equal [ operation.id ], ops.map(&:id) } },
      -> { Runners::Operations.record_result!(RunnerOperation.find(operation.id), status: "ok", result: { "exit_code" => 0 }) }
    )

    operation.reload
    assert operation.completed?
    assert_not_nil operation.delivered_at
    assert_equal({ "exit_code" => 0 }, operation.result)
    assert_nil operation.encrypted_payload
  end

  private

  # Runs `first` in a transaction that commits only once `second`, on another
  # connection, is waiting on a lock. Returns what `second` returned.
  def first_then_second(first, second)
    done = Queue.new
    release = Queue.new
    holder = Thread.new do
      on_own_connection do
        ActiveRecord::Base.transaction do
          first.call
          done << true
          release.pop
        end
      end
    end
    done.pop(timeout: LOCK_WAIT_TIMEOUT) || flunk("the first side never finished")
    pid = Queue.new
    waiter = Thread.new do
      on_own_connection do
        pid << backend_pid
        second.call
      end
    end
    wait_until_waiting_on_lock(pid.pop(timeout: LOCK_WAIT_TIMEOUT))
    release << true
    holder.value
    waiter.value
  ensure
    release << true
    [ holder, waiter ].compact.each(&:join)
  end

  def enqueue
    Runners::Operations.enqueue!(@environment, op: "exec", payload: { "cmd" => [ "true" ] }, deadline_at: 1.minute.from_now)
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
