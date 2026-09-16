# frozen_string_literal: true

require "test_helper"

# What this resource says about a session that is not up yet is the entire
# explanation a person gets for the wait, so a wrong answer here is a wrong
# answer on every screen.
class TerminalSessionResourceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    SessionAdmissionPolicy.sync!(installation_limit: 1)
  end

  def payload(session) = TerminalSessionResource.new(session.reload).to_h

  test "a session nobody has a slot for is reported as waiting for one" do
    holder = create(:terminal_session, user: @user)
    SessionAdmissionService.enqueue!(holder)
    SessionAdmissionService.drain!
    session = create(:terminal_session, user: @user)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!

    assert_equal "queued_for_slot", payload(session)["launchPhase"]
  end

  # The bug this exists for: a session stays in `queued` from the moment the row
  # is written until the container workflow's first activity calls `start!` —
  # right through dispatch. Screens read that state as "waiting for a slot", so
  # an authentication session that was granted its slot in one second spent its
  # whole launch telling the user to wait for capacity, with the user's own
  # limit nowhere near full.
  test "a session whose slot is already granted is not reported as waiting for capacity" do
    session = create(:terminal_session, user: @user)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!

    assert_equal "queued", session.reload.state, "the state alone cannot answer this"
    assert_equal "starting", payload(session)["launchPhase"]
  end

  test "cluster capacity is reported as itself, not as a queue position" do
    session = create(:terminal_session, user: @user)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    session.session_admission.update!(wait_reason: "cluster_capacity")

    assert_equal "cluster_capacity", payload(session)["launchPhase"]
  end

  test "a launch that is running reports neither a wait nor an error" do
    session = create(:terminal_session, user: @user)
    SessionAdmissionService.enqueue!(session)
    SessionAdmissionService.drain!
    session.session_admission.update!(launch_state: "acknowledged", wait_reason: nil)

    assert_equal "running", payload(session)["launchPhase"]
    assert_nil payload(session)["launchError"]
  end

  # A refused preflight used to leave the session sitting in `queued` with
  # nothing but the queue's own explanation on screen.
  test "the launch's own failure is carried to the screen" do
    session = create(:terminal_session, user: @user)
    SessionAdmissionService.enqueue!(session)
    session.session_admission.update!(last_error: "GitHub token expired; reconnect the integration")

    assert_equal "GitHub token expired; reconnect the integration", payload(session)["launchError"]
  end

  test "a session with no admission at all says nothing about slots" do
    session = create(:terminal_session, user: @user)

    assert_nil payload(session)["launchPhase"]
    assert_nil payload(session)["launchError"]
  end
end
