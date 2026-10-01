# frozen_string_literal: true

require "test_helper"

# A Jira delivery all the way to a workflow run: the job re-reads the issue
# through the provider and the pipeline publishes the tracker event.
class Trackers::ProcessDeliveryJobTest < ActiveJob::TestCase
  setup do
    @jira = stub_jira!
    @integration = create(:integration, :jira, :active)
    Trackers::Provisioning.ensure_for!(@integration)
    @project = @integration.project
    @workflow = create(:workflow, scope: @project)
    @column = create(:board_column, board: create(:board, project: @project), name: "Inbox", position: 1)
    @subscription = create(:tracker_subscription, integration: @integration)
  end

  def deliver(changes)
    notification = Trackers::Notification.build(kind: :issue_updated, scope_id: "10000", issue_id: "10100", revision: "31",
                                                changes: changes, actor: { id: "557058:ada", name: "Ada" })
    TrackerDelivery.record(subscription: @subscription, dedup_key: SecureRandom.hex(4), notifications: [ notification ])
  end

  test "a card moved into the intake column starts the workflow on a task linked to the issue" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @project.owner,
                             event_type: "tracker.issue.status_changed", subject_policy: :find_or_create_task, subject_column: @column,
                             filter_predicate: { "change.to.name" => { "op" => "in", "value" => [ "Ready for AI" ] } })
    delivery = deliver([ { field: "status", from: "To Do", to: "Ready for AI", from_id: "1", to_id: "10004" } ])
    WorkflowService.expects(:enqueue).with { |args| (@task = args[:task]) && args[:shared_context].dig("tracker", "provider") == "jira" }
                   .returns(build(:workflow_run))

    Trackers::ProcessDeliveryJob.perform_now(delivery.id)

    assert_equal "processed", delivery.reload.status
    event = TriggerEvent.sole
    assert_equal [ "tracker.issue.status_changed", "Backlog", "Ready for AI" ],
                 [ event.event_type, event.data.dig("change", "from", "name"), event.data.dig("change", "to", "name") ]
    assert_equal [ "ENG-1 It breaks", "https://acme.atlassian.net/browse/ENG-1" ], [ @task.title, @task.external_resources.sole.url ]
  end

  test "an issue-created delivery waits for a create still in flight, and its last attempt publishes it as it stands" do
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @project.owner, event_type: "tracker.issue.created")
    create(:tracker_operation, project_tracker: @integration.project_trackers.find_by!(external_scope_id: "10000"),
                               operation: "create_issue", state: "pending", issue_id: nil)
    notification = Trackers::Notification.build(kind: :issue_created, scope_id: "10000", issue_id: "10100", revision: "1",
                                                actor: { id: "557058:ada", name: "Ada" })
    delivery = TrackerDelivery.record(subscription: @subscription, dedup_key: "created-1", notifications: [ notification ])
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    perform_enqueued_jobs(only: Trackers::ProcessDeliveryJob) { Trackers::ProcessDeliveryJob.perform_later(delivery.id) }

    assert_performed_jobs Trackers::EventPipeline::WRITE_RETRY_ATTEMPTS, only: Trackers::ProcessDeliveryJob
    assert_equal [ "processed", nil ], [ delivery.reload.status, TriggerEvent.sole.data["origin"] ]
  end

  test "a delivery for a connection that is no longer active is skipped" do
    delivery = deliver([ { field: "status", from: "To Do", to: "Done" } ])
    @integration.update!(status: :error)

    Trackers::ProcessDeliveryJob.perform_now(delivery.id)

    assert_equal [ "skipped", { "reason" => "integration inactive" } ], [ delivery.reload.status, delivery.detail ]
  end

  test "a GitHub comment heard by every tracked board starts a run only where the issue is" do
    stub_github_projects!
    integration = create(:integration, :github_projects, :active)
    integration.settings["github_projects"] << { "id" => FakeGithub::ProjectsApi::OPS, "number" => 2, "title" => "Ops" }
    integration.save!
    Trackers::Provisioning.ensure_for!(integration)
    project = integration.project
    create(:trigger_binding, project: project, workflow: create(:workflow, scope: project), created_by: project.owner,
                             event_type: "tracker.comment.created", subject_policy: :none)
    notifications = [ FakeGithub::ProjectsApi::ROADMAP, FakeGithub::ProjectsApi::OPS ].map do |scope|
      Trackers::Notification.build(kind: :comment_created, scope_id: scope, issue_id: "I_kwDOissue1", comment_id: "IC_1",
                                   comment_text: "Hey @aixle-flow", actor: { id: "2", name: "bo" })
    end
    delivery = TrackerDelivery.record(subscription: Trackers::Provider.for(integration).subscription, dedup_key: "gh-1",
                                      notifications: notifications)
    WorkflowService.expects(:enqueue).once.returns(build(:workflow_run))

    Trackers::ProcessDeliveryJob.perform_now(delivery.id)

    assert_equal [ "processed", { "outside_scope" => 1 } ], [ delivery.reload.status, delivery.detail ]
    event = TriggerEvent.sole
    assert_equal [ "Roadmap", true ], [ ProjectTracker.find(event.data.dig("tracker", "id")).name, event.data.dig("comment", "mentions_me") ]
  end
end
