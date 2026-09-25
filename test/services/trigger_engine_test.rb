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

    WorkflowService.expects(:enqueue).with(
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

    WorkflowService.expects(:enqueue).never
    Slack::HelpResponder.expects(:call).once.returns(true)

    TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test",
      data: { "channel" => "OTHER" }, project: @project, dedup_key: "evt-2"
    )
  end

  test "publish replies with help when Slack text is /help and does not start a workflow" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", filter_predicate: { "channel" => "C1" })

    WorkflowService.expects(:enqueue).never
    Slack::HelpResponder.expects(:call).once.returns(true)

    TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test",
      data: { "channel" => "C1", "text" => "<@B0T> /help" }, project: @project, dedup_key: "evt-help"
    )
  end

  test "publish replies with help when no Slack binding matches" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message",
      filter_predicate: { "channel" => "C1", "text" => { "op" => "contains", "value" => "ship" } })

    WorkflowService.expects(:enqueue).never
    Slack::HelpResponder.expects(:call).once.returns(true)

    TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test",
      data: { "channel" => "C1", "text" => "<@B0T>" }, project: @project, dedup_key: "evt-bare"
    )
  end

  test "publish still starts a matching Slack binding and does not help" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message",
      filter_predicate: { "channel" => "C1", "text" => { "op" => "contains", "value" => "ship" } })

    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))
    Slack::HelpResponder.expects(:call).never

    TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test",
      data: { "channel" => "C1", "text" => "<@B0T> please ship it" }, project: @project, dedup_key: "evt-ship"
    )
  end

  test "publish is idempotent on dedup_key — a redelivered event starts the workflow once" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", filter_predicate: {})

    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

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
    WorkflowService.expects(:enqueue).never

    event = TriggerEngine.publish(
      event_type: "slack.message", source: "slack:test",
      data: { "channel" => "C1" }, project: nil, dedup_key: "evt-3"
    )

    assert event.persisted?
  end

  test "a binding with a cooldown starts one run per window and records the rest as skipped" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                             event_type: "slack.message", cooldown_seconds: 60)
    WorkflowService.expects(:enqueue).once.returns(create(:workflow_run, workflow: @workflow, project: @project, user: @user))

    %w[evt-1 evt-2].each do |key|
      TriggerEngine.publish(event_type: "slack.message", source: "slack:test", data: {}, project: @project, dedup_key: key)
    end

    assert_equal %w[skipped started], TriggerDispatch.order(:status).pluck(:status)
    assert_equal({ "reason" => "cooldown" }, TriggerDispatch.find_by(status: "skipped").detail)
  end

  test "a binding starts again once its cooldown has passed" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                             event_type: "slack.message", cooldown_seconds: 60)
    WorkflowService.expects(:enqueue).twice.returns(create(:workflow_run, workflow: @workflow, project: @project, user: @user))

    TriggerEngine.publish(event_type: "slack.message", source: "slack:test", data: {}, project: @project, dedup_key: "evt-1")
    travel 61.seconds do
      TriggerEngine.publish(event_type: "slack.message", source: "slack:test", data: {}, project: @project, dedup_key: "evt-2")
    end

    assert_equal %w[started started], TriggerDispatch.pluck(:status)
  end

  test "fire_for_binding does not start a run without an actor" do
    binding = create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")
    binding.update_column(:created_by_id, nil)
    event = create(:trigger_event, event_type: "slack.message", project: @project)

    WorkflowService.expects(:enqueue).never

    assert_nil TriggerEngine.fire_for_binding(binding: binding, event: event)
  end

  # == record_event ==

  test "record_event persists a normalized event without dispatching" do
    create(:trigger_binding,
      project: @project, workflow: @workflow, created_by: @user, event_type: "slack.message")

    WorkflowService.expects(:enqueue).never

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

    WorkflowService.expects(:enqueue).with(
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

    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

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
    WorkflowService.expects(:enqueue).once.returns(run)

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

    WorkflowService.expects(:enqueue).never

    assert_equal existing_run, TriggerEngine.fire_workflow(
      workflow: @workflow, project: @project, task: nil, actor: @user,
      event: event, source: "column_workflow_binding"
    )
  end

  # == subject_policy ==

  # A generic webhook's data is the sender's own request body.
  test "a webhook cannot hand the run another tenant's assets or reach a Slack integration" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "webhook.received", subject_policy: :none)
    own = create(:asset, scope: @project)
    other_company = create(:company)
    foreign = create(:asset, scope: other_company)
    slack = Integration.create!(provider: :slack, company: other_company, name: "Theirs", status: :active)
    event = create(:trigger_event, event_type: "webhook.received", source: "generic:wh-test", project: @project,
      data: { "input_asset_ids" => [ own.id, foreign.id ], "integration_id" => slack.id,
              "files" => [ { "id" => "F1", "url_private" => "https://files.slack.com/x" } ] })

    Slack::FileIngestor.expects(:new).never
    WorkflowService.expects(:enqueue).with(has_entries(input_asset_ids: [ own.id ])).once.returns(build(:workflow_run))

    TriggerEngine.fire_for_binding(binding: binding, event: event)
  end

  test "subject_policy none starts a task-less project run" do
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", subject_policy: :none)
    event = create(:trigger_event, event_type: "slack.message", project: @project)

    WorkflowService.expects(:enqueue).with(has_entries(task: nil, workflow: @workflow)).once.returns(build(:workflow_run))

    TriggerEngine.fire_for_binding(binding: binding, event: event)
  end

  test "subject_policy create_task creates a card in the subject column and runs on it" do
    board = create(:board, project: @project)
    column = create(:board_column, board: board)
    binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
      event_type: "slack.message", subject_policy: :create_task, subject_column: column,
      subject_title_template: "Triage: {{text}}")
    event = create(:trigger_event, event_type: "slack.message", project: @project, data: { "text" => "fix login" })

    WorkflowService.expects(:enqueue).with(has_entries(workflow: @workflow)).once.returns(build(:workflow_run))

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

    WorkflowService.expects(:enqueue).with(has_entries(task: task, workflow: @workflow)).once.returns(build(:workflow_run))

    TriggerEngine.fire_for_binding(binding: binding, event: event)
  end
end
