# frozen_string_literal: true

require "test_helper"

# Two sessions racing for a runner's one machine (task 8a, decision 2): the
# machine's row lock lets exactly one of them take it, and the other waits for
# capacity. Two attempts of one session racing for two free machines get the
# same one. Each attempt acquires on its own database connection, at once, so
# this test opts out of the transactional wrapper and cleans up after itself.
class Runners::MachinesConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  LOCK_WAIT_TIMEOUT = 10 # seconds

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @runner = create(:runner, :manual, company: @company, created_by: @user)
    @machine = create(:runner_environment, runner: @runner)
    @sessions = create_list(:runner_session, 2, environment: @machine, runner_environment: nil, project: @project, user: @user)
  end

  teardown do
    RunnerEnvironment.where(runner_id: @runner.id).update_all(current_session_id: nil)
    TerminalSession.where(id: @sessions.map(&:id)).delete_all
    Runner.where(id: @runner.id).delete_all
    @project.delete
    @user.company_memberships.delete_all
    UserIdentity.where(user_id: @user.id).delete_all
    UserSession.where(user_id: @user.id).delete_all
    @user.delete
    CompanyAuthPolicy.where(company_id: @company.id).delete_all
    IdentityProvider.where(company_id: @company.id).delete_all
    @company.delete
  end

  test "two sessions racing for one machine: one takes it, the other waits" do
    start = Queue.new
    threads = @sessions.map do |session|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          Runners::Machines.acquire!(TerminalSession.find(session.id))
          :took
        rescue ContainerRuntime::CapacityError
          :waits
        end
      end
    end
    2.times { start << true }

    assert_equal %i[took waits], threads.map(&:value).sort
    taker = @sessions.find { |session| session.reload.runner_environment_id == @machine.id }
    assert_equal taker.id, @machine.reload.current_session_id
    assert_equal 1, TerminalSession.where(id: @sessions.map(&:id)).where.not(runner_environment_id: nil).count
  end

  # The first attempt holds its transaction open once it has taken a machine,
  # until the second, which takes the other free machine, waits on the hold's
  # unique index. The second then loses on that index and answers the hold the
  # first committed.
  test "two attempts of one session racing for two free machines both get the same one" do
    other = create(:runner_environment, runner: @runner)
    session = @sessions.first
    taken = Queue.new
    release = Queue.new
    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          Runners::Machines.acquire!(TerminalSession.find(session.id)).tap do
            taken << true
            release.pop
          end
        end
      end
    end
    taken.pop(timeout: LOCK_WAIT_TIMEOUT) || flunk("the first attempt never took a machine")
    pid = Queue.new
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        pid << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
        Runners::Machines.acquire!(TerminalSession.find(session.id))
      end
    end
    wait_until_waiting_on_lock(pid.pop(timeout: LOCK_WAIT_TIMEOUT))
    release << true

    machines = [ first.value, second.value ]
    assert_equal 1, machines.map(&:id).uniq.size, "both attempts answer the same machine"
    assert_equal session.id, machines.first.reload.current_session_id
    assert_nil RunnerEnvironment.where(id: [ @machine.id, other.id ]).where.not(id: machines.first.id).sole.current_session_id
    assert_equal machines.first.id, session.reload.runner_environment_id
  ensure
    release << true
    [ first, second ].compact.each(&:join)
  end

  private

  # Uncached: the test runs inside the executor, whose query cache would answer
  # every look with the first one's result.
  def wait_until_waiting_on_lock(pid)
    deadline = Time.current + LOCK_WAIT_TIMEOUT
    query = "SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}"
    until ActiveRecord::Base.uncached { ActiveRecord::Base.connection.select_value(query) } == "Lock"
      flunk "backend #{pid} never waited on a lock" if Time.current > deadline
      sleep 0.01
    end
  end
end
