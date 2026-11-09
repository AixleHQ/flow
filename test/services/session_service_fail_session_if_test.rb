# frozen_string_literal: true

require "test_helper"

# SessionService.fail_session_if: failing a session as a compare-and-set, for the checks
# of Sessions::Monitor, which decide on a copy of the row that can be seconds old.
class SessionServiceFailSessionIfTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
  end

  def ready_session(**attrs)
    create(:terminal_session, user: @user, project: @project, session_type: "workflow_step", state: "ready",
                              container_id: "ctr-1", temporal_workflow_id: "wf-1", started_at: 1.hour.ago, **attrs)
  end

  test "fails a session still in the expected state, and wakes its container workflow" do
    session = ready_session
    TemporalService.expects(:send_signal).with(session.workflow_id, :container_finished, nil).once

    assert SessionService.fail_session_if(session: session, expected_state: "ready", error_message: "stuck")

    session.reload
    assert_equal "failed", session.state
    assert_equal "stuck", session.error_message
  end

  # The check read the session, re-checked it, and decided to fail it; finish_session
  # landed before the state change. The state change compares the row's state first.
  test "a session finished after the caller read it stays finished" do
    session = ready_session
    TerminalSession.find(session.id).update!(state: "finished", finished_at: Time.current)
    TemporalService.expects(:send_signal).never

    refute SessionService.fail_session_if(session: session, expected_state: "ready", error_message: "stuck")

    session.reload
    assert_equal "finished", session.state
    assert_nil session.error_message
  end

  test "a session whose row no longer passes the caller's re-check is left as it is" do
    session = ready_session
    TerminalSession.find(session.id).merge_jsonb!(:metadata, "auth_paused_at" => Time.current.iso8601)
    TemporalService.expects(:send_signal).never

    failed = SessionService.fail_session_if(session: session, expected_state: "ready", error_message: "stuck") do |locked|
      !Sessions::AuthPause.paused?(locked)
    end

    refute failed
    assert_equal "ready", session.reload.state
    assert_nil session.error_message
  end

  # An admitted session is failed through its admission (SessionAdmissionService.fail_if!),
  # under the writer lock, with the same compare-and-set.
  test "an admitted session is failed through its admission, and only while it still applies" do
    with_scope_defaults(project: 1)
    session = create(:terminal_session, user: @user, project: @project)
    admission = SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    admission.reload.update!(launch_state: "claimed", claimed_at: Time.current)
    session.update_columns(state: "ready")
    TemporalService.stubs(:cancel_workflow)

    refute SessionService.fail_session_if(session: TerminalSession.find(session.id), expected_state: "running",
                                          error_message: "stuck")
    assert_equal "ready", session.reload.state
    assert_nil admission.reload.stop_requested_at, "nothing is stopped for a session that is not failed"
    assert_nil session.error_message

    assert SessionService.fail_session_if(session: TerminalSession.find(session.id), expected_state: "ready",
                                          error_message: "stuck")
    assert_equal "failed", session.reload.state
    assert_equal "stuck", session.error_message
    assert_not_nil admission.reload.stop_requested_at
  end
end
