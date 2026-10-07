# frozen_string_literal: true

require "test_helper"

class Trackers::EventPipelineTest < ActiveSupport::TestCase
  setup do
    with_azure_devops_enabled
    @integration = create(:integration, :azure_devops, :active)
    @project = @integration.project
    @user = create(:user, company: @project.company)
    @tracker = create(:project_tracker, :primary, integration: @integration, handle: "boards")
    @scope = @tracker.external_scope_id
    @fakes = stub_azure_devops!(integration: @integration)
    @column = create(:board_column, board: create(:board, project: @project), name: "Inbox", position: 1)
    @workflow = create(:workflow, scope: @project)
  end

  def pipeline
    Trackers::EventPipeline.new(@integration)
  end

  def status_change(to: "Resolved", from: "Active", actor: { id: "u1", name: "Ada" }, revision: 4)
    Trackers::Notification.build(kind: :issue_updated, scope_id: @scope, issue_id: "11", revision: revision,
                                 changes: [ { field: "board_column", from: from, to: to } ], actor: actor)
  end

  def intake_binding(workflow: @workflow, **attributes)
    create(:trigger_binding, project: @project, workflow: workflow, created_by: @user,
           event_type: "tracker.issue.status_changed", subject_policy: :find_or_create_task, subject_column: @column,
           filter_predicate: { "change.to.name" => { "op" => "in", "value" => [ "Resolved" ] } }, **attributes)
  end

  test "a status change starts the intake workflow on a new task linked to the issue, with the tracker in context" do
    intake_binding
    WorkflowService.expects(:enqueue).with do |args|
      @task = args[:task]
      args[:shared_context].dig("tracker", "project_tracker_id") == @tracker.id &&
        args[:shared_context].dig("tracker", "change", "to", "name") == "Resolved"
    end.returns(build(:workflow_run))

    events = pipeline.process(status_change)

    event = events.sole
    assert_equal [ "tracker.issue.status_changed", "tracker" ], [ event.event_type, event.source ]
    assert_equal({ "id" => @tracker.id, "handle" => "boards", "provider" => "azure_devops" }, event.data["tracker"])
    assert_equal "11", event.data.dig("issue", "id")
    assert_equal @column, @task.board_column
    assert_equal "11 It breaks", @task.title
    link = @task.external_resources.sole
    assert_equal [ "11", @workflow.id ], [ link.external_id, link.data["workflow_id"] ]
  end

  test "the next event for the same issue reuses the task the first one created" do
    intake_binding
    task = nil
    WorkflowService.stubs(:enqueue).with { |args| task ||= args[:task] }.returns(build(:workflow_run))
    pipeline.process(status_change(revision: 4))

    WorkflowService.expects(:enqueue).with { |args| args[:task] == task }.returns(build(:workflow_run))
    pipeline.process(status_change(from: "Active", revision: 6))

    assert_equal 1, BoardTask.count
  end

  test "a change filtered out by the binding starts nothing" do
    intake_binding
    WorkflowService.expects(:enqueue).never

    pipeline.process(status_change(to: "Active", from: "Resolved"))
  end

  test "with no tracker trigger in the project the issue is not even read" do
    pipeline.process(status_change)

    assert_empty @fakes.work_items.calls
    assert_equal 0, TriggerEvent.count
  end

  test "a change a run of this workflow made does not start it again, but may start another workflow" do
    other = create(:workflow, scope: @project)
    intake_binding(aixle_changes: "other_workflows")
    intake_binding(workflow: other, aixle_changes: "other_workflows")
    create(:tracker_operation, project_tracker: @tracker, issue_id: "11", workflow_id: @workflow.id,
                               change: { "field" => "status", "to" => "Resolved" })

    WorkflowService.expects(:enqueue).with { |args| args[:workflow] == other }.once.returns(build(:workflow_run))

    event = pipeline.process(status_change).sole
    assert_equal [ true, [ @workflow.id ] ], [ event.data.dig("origin", "aixle"), event.data.dig("origin", "chain") ]
  end

  test "by default a binding ignores changes Aixle made" do
    intake_binding
    create(:tracker_operation, project_tracker: @tracker, issue_id: "11", workflow_id: @workflow.id,
                               change: { "field" => "status", "to" => "Resolved" })
    WorkflowService.expects(:enqueue).never

    pipeline.process(status_change)
  end

  test "a chain at the depth limit is not published at all, whatever the bindings allow" do
    intake_binding(aixle_changes: "always")
    create(:tracker_operation, project_tracker: @tracker, issue_id: "11", workflow_id: @workflow.id,
                               chain: [ 1, 2, 3, 4 ], change: { "field" => "status", "to" => "Resolved" })
    WorkflowService.expects(:enqueue).never

    assert_empty pipeline.process(status_change)
    assert_equal 0, TriggerEvent.count
  end

  test "a binding scoped to another tracker does not fire" do
    extra = SecureRandom.uuid
    @integration.azure_devops_installation.update!(allowed_project_ids: [ @scope, extra ])
    @integration.update!(settings: @integration.settings.merge("azure_project_ids" => [ @scope, extra ]))
    other = create(:project_tracker, integration: @integration, external_scope_id: extra, handle: "other")
    intake_binding(project_tracker: other)
    WorkflowService.expects(:enqueue).never

    pipeline.process(status_change)
  end

  test "a generic webhook cannot pose as a tracker event" do
    intake_binding
    WorkflowService.expects(:enqueue).never

    TriggerEngine.publish(event_type: "tracker.issue.status_changed", source: "generic:abc", project: @project,
                          data: { "change" => { "to" => { "name" => "Resolved" } } }, dedup_key: "forged")
  end

  test "a comment event says whether it mentions the connection's own identity" do
    @integration.update!(settings: @integration.settings.merge("tracker_identity" => { "id" => "me-1", "name" => "Aixle" }))
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
           event_type: "tracker.comment.created", filter_predicate: { "comment.mentions_me" => true })
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    notification = Trackers::Notification.build(kind: :comment_created, scope_id: @scope, issue_id: "11", revision: 7,
                                                comment_text: "<div>@Aixle please look</div>", actor: { name: "Ada" })
    event = pipeline.process(notification).sole

    assert_equal [ true, "@Aixle please look" ], [ event.data.dig("comment", "mentions_me"), event.data.dig("comment", "text") ]
  end

  test "a comment is Aixle's only when the ledger names it, so someone's comment right after one of Aixle's still fires" do
    @integration.update!(settings: @integration.settings.merge("tracker_identity" => { "id" => "me-1", "name" => "Aixle" }))
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
           event_type: "tracker.comment.created", filter_predicate: { "comment.mentions_me" => true })
    create(:tracker_operation, project_tracker: @tracker, issue_id: "11", workflow_id: @workflow.id,
                               operation: "add_comment", result_ref: "c-1")
    comment = lambda do |id, actor|
      Trackers::Notification.build(kind: :comment_created, scope_id: @scope, issue_id: "11", revision: id, comment_id: id,
                                   comment_text: "@Aixle please look", actor: actor)
    end
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    own = pipeline.process(comment.call("c-1", { id: "me-1", name: "Aixle" })).sole
    human = pipeline.process(comment.call("c-2", { id: "u1", name: "Ada" })).sole

    assert_equal [ true, true ], [ own.data.dig("origin", "aixle"), own.data.dig("origin", "attributed") ]
    assert_nil human.data["origin"]
  end

  test "a mention inside code is not a mention" do
    @integration.update!(settings: @integration.settings.merge("tracker_identity" => { "id" => "me-1", "name" => "Aixle" }))
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
           event_type: "tracker.comment.created", filter_predicate: { "comment.mentions_me" => true })
    WorkflowService.expects(:enqueue).never

    notification = Trackers::Notification.build(kind: :comment_created, scope_id: @scope, issue_id: "11", revision: 8,
                                                comment_text: "Quoting you: <code>@Aixle please look</code>", actor: { name: "Ada" })
    event = pipeline.process(notification).sole

    assert_equal false, event.data.dig("comment", "mentions_me") # rubocop:disable Minitest/RefuteFalse
  end

  test "an issue created while a create of Aixle's is unanswered waits for it, until the last attempt" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "tracker.issue.created")
    create(:tracker_operation, project_tracker: @tracker, operation: "create_issue", state: "pending", issue_id: nil)
    created = Trackers::Notification.build(kind: :issue_created, scope_id: @scope, issue_id: "11", revision: 1, actor: { name: "Ada" })

    assert_raises(Trackers::EventPipeline::WriteInFlight) do
      Trackers::EventPipeline.new(@integration, wait_for_writes: true).process(created)
    end
    assert_equal 0, TriggerEvent.count

    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))
    assert_nil pipeline.process(created).sole.data["origin"]
  end

  test "a create left pending past any request's timeout holds no event up" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: "tracker.issue.created")
    create(:tracker_operation, project_tracker: @tracker, operation: "create_issue", state: "pending", issue_id: nil,
                               created_at: 3.minutes.ago)
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    created = Trackers::Notification.build(kind: :issue_created, scope_id: @scope, issue_id: "11", revision: 1, actor: { name: "Ada" })
    Trackers::EventPipeline.new(@integration, wait_for_writes: true).process(created)

    assert_equal 1, TriggerEvent.count
  end

  test "an agent's transition sets the state, and the column move it causes is still attributed to its run" do
    intake_binding
    create(:tracker_operation, project_tracker: @tracker, issue_id: "11", workflow_id: @workflow.id,
                               change: { "field" => "status", "to" => "Active" })
    notification = Trackers::Notification.build(
      kind: :issue_updated, scope_id: @scope, issue_id: "11", revision: 9, actor: { name: "Aixle" },
      changes: [ { field: "board_column", from: "New", to: "Resolved" }, { field: "state", from: "New", to: "Active" } ]
    )
    WorkflowService.expects(:enqueue).never

    event = pipeline.process(notification).sole

    assert_equal [ true, true ], [ event.data.dig("origin", "aixle"), event.data.dig("origin", "attributed") ]
    assert_equal({ "from" => "New", "to" => "Active" }, event.data.dig("change", "state"))
  end
end
