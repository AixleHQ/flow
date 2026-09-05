# frozen_string_literal: true

require "test_helper"

class AdmittedPhaseActivityTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    SessionAdmissionPolicy.sync!(installation_limit: 1)
    @session = create(:terminal_session, user: user)
    @admission = SessionAdmissionService.enqueue!(@session)
    SessionAdmissionService.drain!
    @admission.reload.update!(runtime_kind: "ContainerRuntime::DockerRuntime", runtime_id: "runtime-id")
    @runtime = ContainerRuntime::DockerRuntime.new
    ContainerRuntime.stubs(:build).returns(@runtime)
    @activity = Activities::Container::AdmittedPhaseActivity.new
  end

  def cleanup
    @activity.run(Hashie::Mash.new(phase: "cleanup", admission_id: @admission.id))
  end

  test "an absent runtime finalizes session and releases its slot" do
    @runtime.expects(:session_absent?).with("runtime-id").returns(true)
    @runtime.expects(:cleanup_session).never
    cleanup
    assert @admission.reload.released_at
    assert_equal "finished", @session.reload.state
  end

  test "an unresolved external operation prevents cleanup and release" do
    @admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")
    @runtime.expects(:session_absent?).never
    @runtime.expects(:cleanup_session).never
    assert_raises(Temporalio::Error::ApplicationError) { cleanup }
    assert_nil @admission.reload.released_at
  end

  test "accepted deletion is insufficient while runtime remains visible" do
    strategy = mock("strategy")
    @session.stubs(:strategy).returns(strategy)
    # The activity loads its own session instance; stub its lookup, not all instances.
    SessionAdmission.stubs(:find).with(@admission.id).returns(@admission)
    @admission.stubs(:terminal_session).returns(@session)
    strategy.expects(:before_cleanup).returns({})
    @runtime.expects(:session_absent?).with("runtime-id").returns(false).twice
    @runtime.expects(:cleanup_session).with("runtime-id")
    assert_raises(Temporalio::Error::ApplicationError) { cleanup }
    assert_nil @admission.reload.released_at
    assert_equal 1, SessionAdmission.occupied.count
  end
end
