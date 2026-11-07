# frozen_string_literal: true

require "test_helper"

# Two sessions racing for a runner's one machine (task 8a, decision 2): the
# machine's row lock lets exactly one of them take it, and the other waits for
# capacity. Each session acquires on its own database connection, at once, so
# this test opts out of the transactional wrapper and cleans up after itself.
class Runners::MachinesConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @runner = create(:runner, :manual, company: @company, created_by: @user)
    @machine = create(:runner_environment, runner: @runner)
    @sessions = create_list(:runner_session, 2, environment: @machine, runner_environment: nil, project: @project, user: @user)
  end

  teardown do
    RunnerEnvironment.where(id: @machine.id).update_all(current_session_id: nil)
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
end
