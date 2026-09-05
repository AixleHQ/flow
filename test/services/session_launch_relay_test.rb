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

  test "failed preflight releases a reservation when no start was attempted" do
    SessionService.stubs(:revalidate_admission!).raises(SessionAdmissionService::Stopped, "Access revoked")
    TemporalService.expects(:start_workflow).never
    SessionLaunchRelay.dispatch(@admission)
    assert @admission.reload.released_at
    assert_equal "cancelled", @session.reload.state
  end
end
