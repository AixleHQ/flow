# frozen_string_literal: true

require "test_helper"

module Sessions
  class SuspensionTest < ActiveSupport::TestCase
    include CheckpointStorageHelper
    include ActionMailer::TestHelper

    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
      @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                                                                     mode: "interactive", state: "ready")
      use_checkpoint_storage
    end

    teardown { restore_checkpoint_storage }

    test "an interactive agent session can be suspended" do
      assert Suspension.supported?(@session)
    end

    # The app stands in for storage that cannot sign the container's URLs.
    test "a session can be suspended without storage that signs uploads" do
      restore_checkpoint_storage

      assert Suspension.supported?(@session)
    end

    test "a session on an external runner needs storage that signs uploads" do
      @session.runner_id = 42
      assert Suspension.supported?(@session)

      restore_checkpoint_storage
      refute Suspension.supported?(@session)
    end

    test "workflow steps and automatic sessions are not suspended" do
      refute Suspension.supported?(build(:terminal_session, user: @user, session_type: "workflow_step", mode: "interactive"))
      refute Suspension.supported?(build(:terminal_session, user: @user, session_type: "agent_session",
                                                            mode: "non_interactive", initial_prompt: "go"))
    end

    test "the 23-hour limit suspends a session nobody asked to end" do
      @session.update!(ready_at: (Suspension::TIME_LIMIT - 5.minutes).ago)

      assert Suspension.due?(@session, nil)
      assert_equal "time_limit", Suspension.reason(@session)
    end

    test "a session well inside its limit is not suspended unless asked" do
      @session.update!(ready_at: 2.hours.ago)

      refute Suspension.due?(@session, nil)

      @session.update!(metadata: { Suspension::REQUESTED_KEY => Time.current.iso8601 }, finishing_at: Time.current)
      assert Suspension.due?(@session, nil)
      assert_equal "user", Suspension.reason(@session)
    end

    # A crash or a refused launch is not the limit, whenever it happens.
    test "a session ending with an error is never suspended" do
      @session.update!(ready_at: Suspension::TIME_LIMIT.ago)

      refute Suspension.due?(@session, "Container exited unexpectedly")
    end

    test "a finished session past the limit is not mistaken for the limit" do
      @session.update!(ready_at: Suspension::TIME_LIMIT.ago, finishing_at: Time.current)

      refute Suspension.due?(@session, nil)
    end

    test "suspending opens a 30-day restore window and tells the owner" do
      freeze_time do
        assert_enqueued_emails 1 do
          Suspension.suspended!(@session)
        end

        @session.reload
        assert_equal "suspended", @session.state
        assert_equal Time.current, @session.suspended_at
        assert_equal 30.days.from_now, @session.restore_expires_at
        assert_nil @session.container_id
      end
    end

    test "the suspended session becomes restored once the session continuing it is ready" do
      Suspension.suspended!(@session)
      continued = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                                                                      restored_from_session: @session)

      continued.mark_ready!

      assert_equal "restored", @session.reload.state
      assert_equal continued.id, @session.restored_session.id
    end

    test "a restore window that has closed cannot be restored" do
      Suspension.suspended!(@session)
      create_checkpoint(@session)
      assert Suspension.restorable?(@session.reload)

      @session.update!(restore_expires_at: 1.minute.ago)

      refute Suspension.restorable?(@session)
    end

    test "the warning before the limit is computed from when the session became ready" do
      @session.update!(ready_at: 1.hour.ago)

      assert_in_delta (1.hour.ago + Suspension::TIME_LIMIT).to_i, Suspension.suspends_at(@session).to_i, 2
    end
  end
end
