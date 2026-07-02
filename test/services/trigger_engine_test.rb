# frozen_string_literal: true

require "test_helper"

class TriggerEngineTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @workflow = create(:workflow, scope: @project)
  end

  # == publish + dispatch (Slack / webhook path) ==

  test "publish dispatches to a matching binding and starts its workflow" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", filter_predicate: { "channel" => "C1" })

    WorkflowService.expects(:start).with(
      has_entries(workflow: @workflow, mode: :non_interactive, user: @user)
    ).once.returns(build(:workflow_run))

    TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test", subject: "C1",
      data: { "channel" => "C1", "text" => "hi" }, project: @project, dedup_key: "evt-1"
    )

    assert_equal 1, TriggerEvent.where(event_type: "slack.message").count
    assert_equal 1, TriggerDispatch.count
  end

  test "publish does not start a workflow when the predicate does not match" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", filter_predicate: { "channel" => "C1" })

    WorkflowService.expects(:start).never

    TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test",
      data: { "channel" => "OTHER" }, project: @project, dedup_key: "evt-2"
    )
  end

  test "publish is idempotent on dedup_key — a redelivered event starts the workflow once" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", filter_predicate: {})

    WorkflowService.expects(:start).once.returns(build(:workflow_run))

    2.times do
      TriggerEngine.publish(
        event_type: "slack.message", source: "slack:test",
        data: { "channel" => "C1" }, project: @project, dedup_key: "same-key"
      )
    end

    assert_equal 1, TriggerEvent.where(dedup_key: "same-key").count
    assert_equal 1, TriggerDispatch.count
  end

  test "dispatch is a no-op when the event has no project (tenant) scope" do
    WorkflowService.expects(:start).never

    event = TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test",
      data: { "channel" => "C1" }, project: nil, dedup_key: "evt-3"
    )

    assert event.persisted?
  end

  test "fire_for_binding does not start a run without an actor" do
    binding = create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
    binding.update_column(:created_by_id, nil)
    event = create(:trigger_event, event_type: "slack.message", project: @project)

    WorkflowService.expects(:start).never

    assert_nil TriggerEngine.fire_for_binding(binding: binding, event: event)
  end

  # == record_event ==

  test "record_event persists a normalized event without dispatching" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")

    WorkflowService.expects(:start).never

    event = TriggerEngine.record_event(
      event_type: "slack.message", source: "internal",
      data: { "k" => "v" }, project: @project
    )

    assert event.persisted?
    assert_equal({ "k" => "v" }, event.data)
    assert_equal 0, TriggerDispatch.count
  end

  # == legacy column-binding reflection ==

  test "fire_for_column_binding records an event and starts the bound workflow" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    binding = ColumnWorkflowBinding.create!(
      board_column: column, workflow: @workflow, trigger_mode: :auto, cooldown_seconds: 0
    )
    task = create(:board_task, board: board, board_column: column)

    WorkflowService.expects(:start).with(
      has_entries(workflow: @workflow, task: task, mode: :non_interactive)
    ).once.returns(build(:workflow_run))

    TriggerEngine.fire_for_column_binding(binding: binding, task: task, actor: @user)

    assert TriggerEvent.exists?(event_type: "board.column.auto_triggered", board_task_id: task.id)
    assert_equal 1, TriggerDispatch.count
  end

  # == relay / outbox dispatch_pending ==

  test "dispatch_pending marks the event dispatched and is a no-op on re-call" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", filter_predicate: {})
    event = create(:trigger_event, event_type: "slack.message", project: @project, relay_state: "pending")

    WorkflowService.expects(:start).once.returns(build(:workflow_run))

    TriggerEngine.dispatch_pending(event)
    assert_equal "dispatched", event.reload.relay_state

    # Already dispatched → re-call does nothing (no second start).
    TriggerEngine.dispatch_pending(event)
    assert_equal 1, TriggerDispatch.count
  end

  test "fire_workflow resumes a dispatch left matched-but-unstarted (crash recovery)" do
    event = create(:trigger_event, event_type: TriggerEngine::COLUMN_EVENT_TYPE, project: @project)
    # Simulate a crash after the ledger insert but before WorkflowService.start:
    # the dispatch row exists with status "matched" and no run.
    TriggerDispatch.create!(
      trigger_event: event, source: "column_workflow_binding",
      dedup_key: "event:#{event.id}:column_workflow_binding", status: "matched"
    )

    run = build(:workflow_run)
    WorkflowService.expects(:start).once.returns(run)

    result = TriggerEngine.fire_workflow(
      workflow: @workflow, project: @project, task: nil, actor: @user,
      event: event, source: "column_workflow_binding"
    )

    assert_equal run, result
    assert_equal 1, TriggerDispatch.count
  end

  test "fire_workflow does not restart a dispatch that already produced a run" do
    event = create(:trigger_event, event_type: TriggerEngine::COLUMN_EVENT_TYPE, project: @project)
    existing_run = create(:workflow_run, project: @project, workflow: @workflow, user: @user)
    TriggerDispatch.create!(
      trigger_event: event, source: "column_workflow_binding",
      dedup_key: "event:#{event.id}:column_workflow_binding",
      status: "started", workflow_run: existing_run
    )

    WorkflowService.expects(:start).never

    assert_equal existing_run, TriggerEngine.fire_workflow(
      workflow: @workflow, project: @project, task: nil, actor: @user,
      event: event, source: "column_workflow_binding"
    )
  end

  # == subject_policy ==

  test "subject_policy none starts a task-less project run" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", subject_policy: :none)
    event = create(:trigger_event, event_type: "slack.message", project: @project)

    WorkflowService.expects(:start).with(has_entries(task: nil, workflow: @workflow)).once.returns(build(:workflow_run))

    TriggerEngine.fire_for_binding(binding: binding, event: event)
  end

  test "subject_policy create_task creates a card in the subject column and runs on it" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", subject_policy: :create_task, subject_column: column,
      subject_title_template: "Triage: {{text}}")
    event = create(:trigger_event, event_type: "slack.message", project: @project, data: { "text" => "fix login" })

    WorkflowService.expects(:start).with(has_entries(workflow: @workflow)).once.returns(build(:workflow_run))

    assert_difference -> { BoardTask.count }, 1 do
      TriggerEngine.fire_for_binding(binding: binding, event: event)
    end

    task = BoardTask.order(:id).last
    assert_equal column.id, task.board_column_id
    assert_equal "Triage: fix login", task.title
  end

  test "subject_policy existing_task uses the event's task" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    task = create(:board_task, board: board, board_column: column)
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "webhook.received", subject_policy: :existing_task)
    event = create(:trigger_event, event_type: "webhook.received", project: @project, board_task: task)

    WorkflowService.expects(:start).with(has_entries(task: task, workflow: @workflow)).once.returns(build(:workflow_run))

    TriggerEngine.fire_for_binding(binding: binding, event: event)
  end
end
