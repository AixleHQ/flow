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

  def exec_phase
    @activity.run(Hashie::Mash.new(phase: "exec", admission_id: @admission.id, permit_token: @admission.permit_token))
  end

  def stub_exec_raising(error)
    strategy = mock("strategy")
    strategy.stubs(:exec).raises(error)
    @session.stubs(:strategy).returns(strategy)
    SessionAdmission.stubs(:find).with(@admission.id).returns(@admission)
    @admission.stubs(:terminal_session).returns(@session)
    SessionService.stubs(:revalidate_admission!)
  end

  test "a failure that provably never left the process keeps the phase retryable" do
    stub_exec_raising(NoMethodError.new("undefined method 'blank' for nil"))

    assert_raises(Temporalio::Error::ApplicationError) { exec_phase }

    assert_equal "retryable", @admission.session_runtime_operations.find_by(phase: "exec").state
  end

  test "a failure that may have reached the runtime holds the slot for an operator" do
    stub_exec_raising(Errno::ECONNRESET.new("connection reset by peer"))

    assert_raises(Temporalio::Error::ApplicationError) { exec_phase }

    assert_equal "uncertain", @admission.session_runtime_operations.find_by(phase: "exec").state
    assert_raises(SessionAdmissionService::UncertainOperation) { SessionAdmissionService.release!(@admission) }
  end

  test "an absent runtime finalizes session and releases its slot" do
    @runtime.expects(:session_absent?).with("runtime-id").returns(true)
    @runtime.expects(:cleanup_session).never
    cleanup
    assert @admission.reload.released_at
    assert_equal "finished", @session.reload.state
  end

  test "an unresolved operation holds the slot but no longer blocks the deletion" do
    strategy = mock("strategy")
    @session.stubs(:strategy).returns(strategy)
    SessionAdmission.stubs(:find).with(@admission.id).returns(@admission)
    @admission.stubs(:terminal_session).returns(@session)
    @admission.session_runtime_operations.create!(phase: "exec", state: "in_flight")
    strategy.stubs(:before_cleanup).returns({})
    # Refusing to delete was a deadlock: the workload kept the slot honestly
    # occupied, and the operation could never resolve because the deletion that
    # would prove absence was the thing being refused.
    @runtime.expects(:cleanup_session).with("runtime-id")
    @runtime.stubs(:session_absent?).returns(false, true)

    result = cleanup

    assert result[:unresolved_operation], "the reservation must still wait for an operator"
    assert_nil @admission.reload.released_at
  end

  test "an unresolved external operation never releases the slot, even once the runtime is gone" do
    @admission.session_runtime_operations.create!(phase: "create_container", state: "uncertain")
    @runtime.expects(:session_absent?).returns(true)
    @runtime.expects(:cleanup_session).never

    result = cleanup

    # AD-5: a late create must never find its slot handed to someone else, so
    # an unprovable operation keeps the reservation until an operator resolves it.
    assert result[:unresolved_operation]
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

    result = cleanup

    assert result[:cleanup_pending], "an unconfirmed delete must report back, not fail the execution"
    assert_nil @admission.reload.released_at
    assert_equal 1, SessionAdmission.occupied.count
  end

  test "a session that finished settles its own state while the runtime is still going away" do
    strategy = mock("strategy")
    @session.stubs(:strategy).returns(strategy)
    SessionAdmission.stubs(:find).with(@admission.id).returns(@admission)
    @admission.stubs(:terminal_session).returns(@session)
    strategy.stubs(:before_cleanup).returns({})
    @runtime.stubs(:session_absent?).returns(false)
    @runtime.stubs(:cleanup_session)

    cleanup

    assert_equal "finished", @session.reload.state, "queue latency must not leave the UI on a dead session"
    assert_nil @admission.reload.released_at, "capacity is only returned once the runtime is confirmed gone"
  end

  test "output collection does not repeat when cleanup is retried" do
    strategy = mock("strategy")
    @session.stubs(:strategy).returns(strategy)
    SessionAdmission.stubs(:find).with(@admission.id).returns(@admission)
    @admission.stubs(:terminal_session).returns(@session)
    strategy.expects(:before_cleanup).once.returns({})
    @runtime.stubs(:cleanup_session)
    @runtime.stubs(:session_absent?).returns(false)
    cleanup

    @runtime.stubs(:session_absent?).returns(false, true)
    cleanup

    assert @admission.reload.released_at
  end
end
