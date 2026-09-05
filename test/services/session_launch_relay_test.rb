# frozen_string_literal: true

require "test_helper"

class SessionLaunchRelayTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    SessionAdmissionPolicy.sync!(installation_limit: 1)
    @session = create(:terminal_session, user: @user)
    @admission = SessionAdmissionService.enqueue!(@session)
    SessionAdmissionService.drain!
    SessionService.stubs(:revalidate_admission!)
  end

  test "lost start response retries the same workflow identity and reservation" do
    TemporalService.expects(:start_workflow).with do |_workflow, input, options|
      input[:admission_id] == @admission.id && options[:id] == @session.workflow_id && options[:reject_duplicate]
    end.returns({ ok: false, error: "transport timeout" }, { ok: true, run_id: "existing-run" }).twice
    SessionLaunchRelay.dispatch(@admission)
    assert_nil @admission.reload.released_at
    @admission.update!(claimed_at: 3.minutes.ago)
    SessionLaunchRelay.dispatch(@admission)
    assert_equal "acknowledged", @admission.reload.launch_state
    assert_equal "existing-run", @session.reload.temporal_run_id
    assert_equal 1, SessionAdmission.occupied.count
  end

  test "the launch path refreshes agent credentials before building a manifest" do
    SessionService.unstub(:revalidate_admission!)
    # Preflight only CHECKS a credential; a workflow-step container that starts
    # on a token minutes from expiry fails halfway through its own run.
    SessionService.expects(:revalidate_admission!)
                  .with { |session, **kwargs| session.id == @session.id && kwargs[:refresh_tokens] == true }
                  .raises(SessionAdmissionService::Stopped, "checked")
    TemporalService.expects(:start_workflow).never

    SessionLaunchRelay.dispatch(@admission)
  end

  test "a queued agent login is not blocked by the credential it exists to replace" do
    SessionService.unstub(:revalidate_admission!)
    broken = create(:agent_credential, user: @user, company: @user.companies.first,
                    agent_type: "claude_code", status: "error")
    @session.update!(session_type: "agent_session", agent_type: broken.agent_type)

    # A normal session behind a broken credential is stopped at the gate...
    assert_raises(AgentCredential::PreflightError) { SessionService.revalidate_admission!(@session.reload) }

    # ...but the login that exists to replace it must get through, or the queue
    # traps the user with no way to fix the thing blocking them.
    @session.update!(session_type: "auth_setup")
    assert_nothing_raised { SessionService.revalidate_admission!(@session.reload) }
  end

  test "failed preflight releases a reservation when no start was attempted" do
    SessionService.stubs(:revalidate_admission!).raises(SessionAdmissionService::Stopped, "Access revoked")
    TemporalService.expects(:start_workflow).never
    SessionLaunchRelay.dispatch(@admission)
    assert @admission.reload.released_at
    assert_equal "cancelled", @session.reload.state
  end
end
