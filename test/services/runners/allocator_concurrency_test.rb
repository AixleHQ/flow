# frozen_string_literal: true

require "test_helper"

# Two sessions racing for the one environment a provisioned runner may make, and
# two machines racing for one registration token (docs/design/agent-runtimes/
# runner-coder.md §5.1, §8.4). Each attempt runs on its own database connection,
# at once, so this test opts out of the transactional wrapper and cleans up after
# itself. The `manual` side of the same races is Runners::MachinesConcurrencyTest.
class Runners::AllocatorConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  LOCK_WAIT_TIMEOUT = 10 # seconds

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @runner = create(:runner, :coder, company: @company, created_by: @user, max_environments: 1, max_concurrency: 2)
    @integration = @runner.integration
    @carrier = create(:runner_environment, :allocated, runner: @runner, state: "gone")
    @sessions = create_list(:runner_session, 2, environment: @carrier, runner_environment: nil, project: @project, user: @user)
    @adapter = with_fake_provisioned_adapter
  end

  teardown do
    RunnerEnvironment.where(runner_id: @runner.id).update_all(current_session_id: nil)
    TerminalSession.where(id: @sessions.map(&:id)).delete_all
    Runner.where(id: @runner.id).delete_all
    @integration.delete
    @project.delete
    @user.company_memberships.delete_all
    UserIdentity.where(user_id: @user.id).delete_all
    UserSession.where(user_id: @user.id).delete_all
    @user.delete
    CompanyAuthPolicy.where(company_id: @company.id).delete_all
    IdentityProvider.where(company_id: @company.id).delete_all
    @company.delete
  end

  test "two sessions racing for a runner that may make one environment: one gets it made, the other waits for capacity" do
    start = Queue.new
    threads = @sessions.map do |session|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          Runners::Allocator.acquire!(TerminalSession.find(session.id))
          :ready
        rescue Runners::Allocator::Pending
          :made
        rescue ContainerRuntime::CapacityError => e
          e.reason
        end
      end
    end
    2.times { start << true }

    assert_equal %w[made runner_capacity], threads.map(&:value).map(&:to_s).sort
    made = RunnerEnvironment.where(runner_id: @runner.id).where.not(id: @carrier.id).sole
    assert_equal 1, TerminalSession.where(id: @sessions.map(&:id)).where(runner_environment_id: made.id).count
    assert_equal made.current_session_id, TerminalSession.where(id: @sessions.map(&:id)).find_by(runner_environment_id: made.id).id
  end

  test "two machines racing for one bound registration token: one registers into the row, the other is refused" do
    environment = RunnerEnvironment.create!(runner: @runner, origin: :allocated, state: :provisioning, key: "race-1", external_id: "ws-race")
    token = Runners::Credentials.mint_registration!(@runner, environment: environment)
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          credential = RunnerCredential.find_by_token(token, kind: :registration)
          Runners::Registration.register!(credential, name: "ws-race", os: "linux", arch: "amd64", facts: {},
                                                      auto_update: true, runner_version: "1.4.0", protocol_version: "1")
          :registered
        rescue Runners::Credentials::Refused => e
          e.reason
        end
      end
    end
    2.times { start << true }

    assert_equal %w[invalid_token registered], threads.map(&:value).map(&:to_s).sort
    assert_equal "booting", environment.reload.state
    assert_equal 1, RunnerCredential.where(runner_environment_id: environment.id, kind: "access").count
  end
end
