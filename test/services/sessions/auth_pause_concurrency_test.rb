# frozen_string_literal: true

require "test_helper"

module Sessions
  # Two auth-paused sessions of one workflow run are unpaused at the same moment, each on its
  # own database connection. Each unpause removes its own marker and resumes the run only when
  # no other step of it is still paused. Unserialized, each one sees the other's marker, which
  # is not committed yet, as still set, and neither resumes the run: the run stays paused with
  # no paused session left to release it. Sessions::AuthPause#transition serializes them on the
  # run's row lock, so the second sees the first's marker gone and resumes the run.
  #
  # The first unpause is held after it has decided not to resume the run, until the second is
  # seen waiting on a lock. The racing work commits on its own connections, so this test opts
  # out of the transactional wrapper and cleans up after itself.
  class AuthPauseConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    LOCK_WAIT_TIMEOUT = 10 # seconds

    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @workflow = create(:workflow, scope: @project)
      @step = create(:step, workflow: @workflow)
      @run = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "running",
                                   started_at: 1.hour.ago)
      @sessions = Array.new(2) { paused_step_session }
      @run.pause!
      @runtime = stub_container_runtime
    end

    # Nil-safe: a setup that failed half way still cleans up what it created.
    teardown do
      cleanup_runtime_overrides
      StepRun.where(workflow_run_id: @run.id).delete_all if @run
      TerminalSession.where(user_id: @user.id).delete_all if @user
      WorkflowRun.where(id: @run.id).delete_all if @run
      Step.where(workflow_id: @workflow.id).delete_all if @workflow
      Workflow.where(id: @workflow.id).delete_all if @workflow
      # Before the user: projects.owner_id references it. Rows are deleted directly, so
      # `dependent: :destroy` never fires and every dependent is cleared by hand.
      @project&.delete
      @user&.company_memberships&.delete_all
      UserIdentity.where(user_id: @user.id).delete_all if @user
      UserSession.where(user_id: @user.id).delete_all if @user
      @user&.delete
      CompanyAuthPolicy.where(company_id: @company.id).delete_all if @company
      IdentityProvider.where(company_id: @company.id).delete_all if @company
      @company&.delete
    end

    test "two sessions of one run unpaused concurrently resume the run" do
      first_session, second_session = @sessions
      decided = Queue.new
      release = Queue.new
      first = Thread.new do
        on_own_connection do
          pause = AuthPause.new(TerminalSession.find(first_session.id), runtime: @runtime)
          # Inside the first unpause's transaction, its marker removed but not committed, once it
          # has looked for another paused step of the run.
          pause.define_singleton_method(:other_step_auth_paused?) do |run|
            super(run).tap do
              decided << true
              release.pop
            end
          end
          pause.unpause_quietly(episode: AuthPause.episode(first_session))
        end
      end
      decided.pop(timeout: LOCK_WAIT_TIMEOUT) || flunk("the first unpause never got inside its transaction")

      pid = Queue.new
      second = Thread.new do
        on_own_connection do
          pid << backend_pid
          AuthPause.new(TerminalSession.find(second_session.id), runtime: @runtime)
                   .unpause_quietly(episode: AuthPause.episode(second_session))
        end
      end
      wait_until_waiting_on_lock_or_done(pid.pop(timeout: LOCK_WAIT_TIMEOUT), second)
      release << true

      assert first.value, "the first session is unpaused"
      assert second.value, "the second session is unpaused"
      refute AuthPause.paused?(first_session.reload)
      refute AuthPause.paused?(second_session.reload)
      assert_equal "running", @run.reload.state, "no paused run is left without a paused session"
    ensure
      release << true
      [ first, second ].compact.each(&:join)
    end

    private

    def paused_step_session
      session = create(:terminal_session, session_type: "workflow_step", state: "ready", mode: "non_interactive",
                                          user: @user, project: @project, company: @company, agent_type: "claude_code",
                                          container_id: "ctr-#{SecureRandom.hex(3)}", started_at: 1.hour.ago,
                                          initial_prompt: "do the work")
      create(:step_run, :running, workflow_run: @run, step: @step, terminal_session: session)
      session.merge_jsonb!(:metadata, "auth_paused_at" => 5.minutes.ago.iso8601)
      session
    end

    def on_own_connection(&)
      ActiveRecord::Base.connection_pool.with_connection(&)
    end

    def backend_pid
      ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
    end

    # The second unpause waits on the run's lock while the first holds it. Without that lock it
    # does not wait and finishes instead, and the run is left paused, which the test asserts
    # against. Uncached: the test runs inside the executor, whose query cache would answer every
    # poll with the first one's result.
    def wait_until_waiting_on_lock_or_done(pid, thread)
      deadline = Time.current + LOCK_WAIT_TIMEOUT
      query = "SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}"
      until !thread.alive? || ActiveRecord::Base.uncached { ActiveRecord::Base.connection.select_value(query) } == "Lock"
        flunk "backend #{pid} neither waited on a lock nor finished" if Time.current > deadline
        sleep 0.01
      end
    end
  end
end
