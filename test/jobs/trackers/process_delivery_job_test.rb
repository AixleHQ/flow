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

  test "a delivery for a connection that is no longer active is skipped" do
    delivery = deliver([ { field: "status", from: "To Do", to: "Done" } ])
    @integration.update!(status: :error)

    Trackers::ProcessDeliveryJob.perform_now(delivery.id)

    assert_equal [ "skipped", { "reason" => "integration inactive" } ], [ delivery.reload.status, delivery.detail ]
  end
end
