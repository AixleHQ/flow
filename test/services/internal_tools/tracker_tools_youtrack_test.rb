# frozen_string_literal: true

require "test_helper"

# The tracker tools and the event pipeline over a YouTrack connection, through
# the real provider.
class InternalTools::TrackerToolsYoutrackTest < ActiveSupport::TestCase
  APP = FakeYoutrack::Api::APP
  ISSUE_1 = FakeYoutrack::Api::ISSUE_1

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @youtrack = stub_youtrack!
    @integration = create(:integration, :youtrack, :active)
    Trackers::Provisioning.ensure_for!(@integration)
    @project = @integration.project
    @user = create(:user, company: @project.company)
    @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                      mode: "non_interactive", initial_prompt: "work")
    @workflow = create(:workflow, scope: @project)
  end

  def run_tool(klass, **params)
    result = klass.new(params: params, session: @session).execute
    assert_equal 0, result[:exit_code], result[:stderr]
    JSON.parse(result[:stdout])
  end

  def bind(event_type)
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, event_type: event_type)
  end

  def status_change(to)
    Trackers::Notification.build(kind: :issue_updated, scope_id: APP, issue_id: "APP-1", revision: "1790000000000",
                                 changes: [ { field: "status", from: "Submitted", to: to } ], actor: { login: "jdoe" })
  end

  test "the connection's projects are its trackers, and a readable id picks its project" do
    trackers = run_tool(InternalTools::TrackerList)["trackers"]
    comment = run_tool(InternalTools::TrackerAddComment, issue: "OPS-1", body: "Rotated")

    assert_equal [ [ "application", "youtrack", true ], [ "operations", "youtrack", false ] ],
                 trackers.map { |t| t.values_at("handle", "provider", "primary") }
    assert_equal [ "operations", "add_comment" ], [ TrackerOperation.sole.project_tracker.handle, TrackerOperation.sole.operation ]
    assert_equal "Rotated", comment["body"]
  end

  test "a status change YouTrack's history confirms is published with who made it; a forged one is not" do
    bind("tracker.issue.status_changed")
    WorkflowService.stubs(:enqueue)
    @youtrack.record_activity(ISSUE_1, field: "State", added: "Ready for AI", removed: "Submitted")

    Trackers::EventPipeline.new(@integration).process(status_change("Fixed"))
    assert_equal 0, TriggerEvent.count

    Trackers::EventPipeline.new(@integration).process(status_change("Ready for AI"))
    event = TriggerEvent.sole
    assert_equal [ "Ready for AI", "todo", "jdoe", false ],
                 [ event.data.dig("change", "to", "name"), event.data.dig("change", "to", "category"),
                   event.data.dig("actor", "login"), event.data.dig("actor", "is_me") ]
    assert_equal [ "youtrack", "https://acme.youtrack.cloud", ISSUE_1 ],
                 event.data["external_resource"].values_at("provider", "instance", "external_id")
  end

  test "the agent's own transition comes back attributed to its run" do
    run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
    create(:step_run, workflow_run: run, step: create(:step, :non_interactive, workflow: @workflow), terminal_session: @session.reload)
    bind("tracker.issue.status_changed")
    WorkflowService.expects(:enqueue).never

    run_tool(InternalTools::TrackerTransitionIssue, issue: "APP-1", status: "In Progress")
    @youtrack.record_activity(ISSUE_1, field: "State", added: "In Progress", removed: "Ready for AI", author: FakeYoutrack::Api::BOT)
    Trackers::EventPipeline.new(@integration).process(status_change("In Progress"))

    origin = TriggerEvent.sole.data["origin"]
    assert_equal [ true, true, run.id ], origin.values_at("aixle", "attributed", "workflow_run_id")
  end

  test "a delivery naming an issue of another project is processed as outside the scope and starts nothing" do
    bind("tracker.issue.created")
    subscription = Trackers::Youtrack::Subscriptions.new(@integration).ensure!.find { |s| s.external_scope_id == APP }
    notifications = Trackers::Youtrack::Notifications.parse(youtrack_event("issue_created", issue: "OPS-1"),
                                                            project: @integration.settings["youtrack_projects"].first)
    delivery = TrackerDelivery.record(subscription: subscription, dedup_key: "d-1", notifications: notifications)

    Trackers::ProcessDeliveryJob.perform_now(delivery.id)

    assert_equal [ "processed", { "outside_scope" => 1 } ], [ delivery.reload.status, delivery.detail ]
    assert_equal 0, TriggerEvent.count
  end

  test "a project renamed in YouTrack is searched and recognised under its new short name" do
    @youtrack.add_issue(id: "2-60", key: "WEB-60", title: "Renamed", state: "Submitted",
                        project: { id: APP, key: "WEB", name: "Application" })

    run_tool(InternalTools::TrackerGetIssue, issue: "2-60")

    assert_equal "WEB", @integration.reload.settings["youtrack_projects"].first["key"]
    assert_equal "WEB", ProjectTracker.find_by!(integration: @integration, external_scope_id: APP).external_scope_key
    assert Trackers::Provider.for(@integration).owns_reference?(APP, "WEB-61")
  end

  test "a comment's text and author are read from YouTrack, not from the delivery" do
    bind("tracker.comment.created")
    WorkflowService.stubs(:enqueue)
    comment = @youtrack.add_comment_by(ISSUE_1, text: "@aixle please look")
    notification = Trackers::Notification.build(kind: :comment_created, scope_id: APP, issue_id: "APP-1", comment_id: comment[:id],
                                                comment_text: "something else", actor: { login: "aixle" })

    Trackers::EventPipeline.new(@integration).process(notification)

    data = TriggerEvent.sole.data
    assert_equal [ "@aixle please look", true, "jdoe", false ],
                 [ data.dig("comment", "text"), data.dig("comment", "mentions_me"), data.dig("actor", "login"), data.dig("actor", "is_me") ]
  end
end
