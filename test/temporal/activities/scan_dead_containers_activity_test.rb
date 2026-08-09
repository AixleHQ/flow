# frozen_string_literal: true

require "test_helper"

module Activities
  module Session
    class ScanDeadContainersActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @runtime = stub_container_runtime

        # Sessions here carry a temporal_workflow_id, so the fail path signals the
        # container workflow. TemporalService is the app-owned seam (docs/testing.md
        # §4); the signalling tests replace this with an expectation.
        TemporalService.stubs(:send_signal).returns({ ok: true })
      end

      teardown do
        cleanup_runtime_overrides
      end

      def ready_session(status: nil, **overrides)
        session = create(:terminal_session, :running,
          user: @user,
          state: "ready",
          session_type: "agent_session",
          started_at: 10.minutes.ago,
          temporal_workflow_id: "wf-#{SecureRandom.hex(4)}",
          **overrides)
        @runtime.set_container_status(status, container_id: session.container_id) if status
        session
      end

      # == First sighting is never fatal ==

      test "records a first sighting instead of failing the session" do
        session = ready_session(status: :missing)

        result = run_activity(ScanDeadContainersActivity)

        assert_equal 1, result[:checked]
        assert_equal 0, result[:failed]
        session.reload
        assert_equal "ready", session.state
        assert session.metadata["container_dead_since"].present?,
               "first sighting must be recorded so the next sweep can confirm it"
      end

      test "fails a session whose container is still gone after the confirmation delay" do
        session = ready_session(status: :missing)

        run_activity(ScanDeadContainersActivity)

        travel ScanDeadContainersActivity::CONFIRMATION_DELAY + 1.minute do
          result = run_activity(ScanDeadContainersActivity)

          assert_equal 1, result[:failed]
        end

        session.reload
        assert_equal "failed", session.state
        assert_match(/vanished/, session.error_message)
        assert_not_nil session.finished_at
      end

      test "fails a session whose pod left the Running phase" do
        # restartPolicy: Never — a killed agent leaves a terminated pod behind
        # rather than disappearing.
        session = ready_session(status: :terminated)

        run_activity(ScanDeadContainersActivity)
        travel(ScanDeadContainersActivity::CONFIRMATION_DELAY + 1.minute) { run_activity(ScanDeadContainersActivity) }

        session.reload
        assert_equal "failed", session.state
        assert_match(/no longer running/, session.error_message)
      end

      # == The signal that reclaims the container ==

      test "signals the session's own container workflow, not only the parent workflow run" do
        project = create(:project, owner: @user, company: @company)
        workflow_run = create(:workflow_run, project: project, user: @user)
        step = create(:step, workflow: workflow_run.workflow)
        step_run = create(:step_run, workflow_run: workflow_run, step: step)
        session = ready_session(status: :missing, session_type: "workflow_step")
        step_run.update!(terminal_session: session)

        # The parent run's execution completes the step...
        TemporalService.expects(:send_signal)
          .with("workflow-execution-#{workflow_run.id}", :container_finished, step_run.id).once
        # ...and the session's OWN container workflow gets woken up, which is what
        # runs its cleanup phase and deletes the pod, Service and IngressRoute.
        # Without it that execution waits out a 23-hour signal timeout and the
        # Kubernetes objects leak.
        TemporalService.expects(:send_signal)
          .with(session.workflow_id, :container_finished, step_run.id).once

        run_activity(ScanDeadContainersActivity)
        travel(ScanDeadContainersActivity::CONFIRMATION_DELAY + 1.minute) { run_activity(ScanDeadContainersActivity) }

        assert_equal "failed", session.reload.state
      end

      # == Healthy sessions are left alone ==

      test "leaves a running container alone and never records a sighting" do
        session = ready_session(status: :running)

        result = run_activity(ScanDeadContainersActivity)

        assert_equal 0, result[:failed]
        session.reload
        assert_equal "ready", session.state
        assert_nil session.metadata["container_dead_since"]
      end

      test "treats a container that has not started yet as alive" do
        session = ready_session(status: :starting)

        travel(ScanDeadContainersActivity::CONFIRMATION_DELAY + 1.minute) { run_activity(ScanDeadContainersActivity) }
        travel(2 * ScanDeadContainersActivity::CONFIRMATION_DELAY) { run_activity(ScanDeadContainersActivity) }

        assert_equal "ready", session.reload.state
      end

      test "clears the sighting when the container turns out to be alive" do
        session = ready_session(status: :missing)

        run_activity(ScanDeadContainersActivity)
        @runtime.set_container_status(:running, container_id: session.container_id)

        travel(ScanDeadContainersActivity::CONFIRMATION_DELAY + 1.minute) do
          run_activity(ScanDeadContainersActivity)
        end

        session.reload
        assert_equal "ready", session.state
        assert_nil session.metadata["container_dead_since"],
               "an alive sighting must reset confirmation, so two dead sightings are never split by a live one"
      end

      test "does not fail a session when the runtime cannot answer" do
        session = ready_session(status: :missing)

        run_activity(ScanDeadContainersActivity)
        # Control plane unreachable: :unknown is not evidence of death.
        @runtime.set_container_status(:unknown, container_id: session.container_id)

        travel(ScanDeadContainersActivity::CONFIRMATION_DELAY + 1.minute) do
          result = run_activity(ScanDeadContainersActivity)

          assert_equal 0, result[:failed]
        end

        assert_equal "ready", session.reload.state
      end

      # == Scope ==

      test "ignores sessions younger than MIN_AGE" do
        session = ready_session(status: :missing, started_at: 30.seconds.ago)

        result = run_activity(ScanDeadContainersActivity)

        assert_equal 0, result[:checked]
        session.reload
        assert_equal "ready", session.state
        assert_nil session.metadata["container_dead_since"]
      end

      test "ignores sessions without a container_id" do
        session = ready_session(status: :missing, container_id: nil)

        result = run_activity(ScanDeadContainersActivity)

        assert_equal 0, result[:checked]
        assert_equal "ready", session.reload.state
      end

      test "ignores sessions that already reached a terminal state" do
        finished = create(:terminal_session, user: @user, state: "finished",
          container_id: "container-finished", started_at: 1.hour.ago)
        finishing = create(:terminal_session, :finishing, user: @user,
          started_at: 1.hour.ago, finishing_at: 30.minutes.ago)
        @runtime.set_container_status(:missing)

        result = run_activity(ScanDeadContainersActivity)

        assert_equal 0, result[:checked]
        assert_equal "finished", finished.reload.state
        assert_equal "finishing", finishing.reload.state
      end

      test "keeps sweeping after one session's lookup blows up" do
        ready_session(status: StandardError.new("control plane unreachable"))
        dead = ready_session(status: :missing)

        result = run_activity(ScanDeadContainersActivity)

        assert_equal 2, result[:checked]
        assert dead.reload.metadata["container_dead_since"].present?,
               "a failure on one session must not abandon the rest of the sweep"
      end
    end
  end
end
