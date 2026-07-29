# frozen_string_literal: true

require "test_helper"

class OutboxRelayTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @task = create(:board_task, board: @board, board_column: @column)
  end

  # A pending column-trigger event as a producer would have recorded it.
  def pending_column_event(created_at: Time.current, attempts: 0)
    create(:trigger_event,
      event_type: TriggerEngine::COLUMN_EVENT_TYPE,
      source: "column_workflow_binding:1",
      data: { "workflow_id" => @workflow.id, "column_id" => @column.id },
      project: @project, board_task: @task, actor: @user,
      relay_state: "pending", relay_attempts: attempts, created_at: created_at)
  end

  test "drain dispatches a pending event stuck past the grace window" do
    event = pending_column_event(created_at: 5.minutes.ago)

    WorkflowService.expects(:start).with(
      has_entries(workflow: @workflow, task: @task, user: @user, mode: :non_interactive)
    ).once.returns(build(:workflow_run))

    result = OutboxRelay.drain

    assert_equal 1, result[:swept]
    assert_equal 1, result[:dispatched]
    assert_equal "dispatched", event.reload.relay_state
    assert_not_nil event.dispatched_at
    assert_equal 1, TriggerDispatch.count
  end

  test "drain leaves a fresh pending event alone until the grace window passes" do
    event = pending_column_event(created_at: Time.current)

    WorkflowService.expects(:start).never

    result = OutboxRelay.drain

    assert_equal 0, result[:swept]
    assert_equal "pending", event.reload.relay_state
  end

  test "drain ignores already-dispatched events" do
    create(:trigger_event, event_type: TriggerEngine::COLUMN_EVENT_TYPE,
      project: @project, board_task: @task, actor: @user,
      data: { "workflow_id" => @workflow.id }, relay_state: "dispatched", created_at: 5.minutes.ago)

    WorkflowService.expects(:start).never

    assert_equal 0, OutboxRelay.drain[:swept]
  end

  test "draining the same event twice starts the workflow once (idempotent via dedup)" do
    event = pending_column_event(created_at: 5.minutes.ago)

    WorkflowService.expects(:start).once.returns(build(:workflow_run))

    OutboxRelay.drain
    # Force it back to pending to simulate a relay that crashed after starting the
    # run but before marking the event dispatched; the re-dispatch must not re-fire.
    event.update_columns(relay_state: "pending")
    OutboxRelay.drain

    assert_equal 1, TriggerDispatch.count
    assert_equal "dispatched", event.reload.relay_state
  end

  test "drain skips events that have exhausted their relay attempts" do
    pending_column_event(created_at: 5.minutes.ago, attempts: TriggerEvent::RELAY_MAX_ATTEMPTS)

    WorkflowService.expects(:start).never

    assert_equal 0, OutboxRelay.drain[:swept]
  end

  test "a failing dispatch is retried with an incremented attempt and left pending" do
    event = pending_column_event(created_at: 5.minutes.ago)

    WorkflowService.expects(:start).raises(StandardError, "temporal down")

    OutboxRelay.drain

    event.reload
    assert_equal "pending", event.relay_state
    assert_equal 1, event.relay_attempts
    assert_equal "temporal down", event.relay_error
  end
end
