# frozen_string_literal: true

require "test_helper"

# The tracker tools over a Jira connection, through the real provider.
class InternalTools::TrackerToolsJiraTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @jira = stub_jira!
    @integration = create(:integration, :jira, :active)
    Trackers::Provisioning.ensure_for!(@integration)
    @project = @integration.project
    @user = create(:user, company: @project.company)
    @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                      mode: "non_interactive", initial_prompt: "work")
  end

  def run_tool(klass, **params)
    result = klass.new(params: params, session: @session).execute
    assert_equal 0, result[:exit_code], result[:stderr]
    JSON.parse(result[:stdout])
  end

  # The session runs a step of a workflow run, whose writes the ledger attributes.
  def agent_run!
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    create(:step_run, workflow_run: run, step: create(:step, :non_interactive, workflow: workflow), terminal_session: @session)
    @session.reload
    [ workflow, run ]
  end

  # Jira's webhook for a change, delivered and processed as the receiver does it.
  def deliver(subscription, **notification)
    delivery = TrackerDelivery.record(subscription: subscription, dedup_key: SecureRandom.hex(4),
                                      notifications: [ Trackers::Notification.build(scope_id: "10000", **notification) ])
    Trackers::ProcessDeliveryJob.perform_now(delivery.id)
  end

  test "the connection's projects are its trackers, the first one primary" do
    trackers = run_tool(InternalTools::TrackerList)["trackers"]

    assert_equal [ [ "engineering", "jira", true ], [ "operations", "jira", false ] ],
                 trackers.map { |t| t.values_at("handle", "provider", "primary") }
  end

  test "an issue URL picks its tracker, and the agent moves it by column name" do
    moved = run_tool(InternalTools::TrackerTransitionIssue, issue: "https://acme.atlassian.net/browse/ENG-1", status: "Doing")

    assert_equal [ "ENG-1", "Doing", "In Progress" ], [ moved["key"], moved.dig("status", "name"), moved.dig("fields", "state") ]
    operation = TrackerOperation.sole
    assert_equal [ "engineering", { "field" => "status", "to" => "Doing" } ], [ operation.project_tracker.handle, operation.change ]
  end

  # A connection made with a person's Atlassian account acts as that person, so
  # only the ledger tells the agent's change from theirs — and Jira may deliver
  # the webhook before the transition call has returned.
  test "a transition whose webhook arrives while it is in flight is still the run's own change" do
    @integration.update!(settings: @integration.settings.merge("auth_mode" => "oauth", "dedicated_identity" => false))
    workflow, run = agent_run!
    create(:trigger_binding, project: @project, workflow: workflow, created_by: @user,
                             event_type: "tracker.issue.status_changed")
    subscription = create(:tracker_subscription, integration: @integration)
    @jira.before_answering(:transition) do
      deliver(subscription, kind: :issue_updated, issue_id: "10100", revision: "40", actor: { id: "557058:ada", name: "Ada" },
                            changes: [ { field: "status", from: "Ready for AI", to: "In Progress", from_id: "10004", to_id: "3" } ])
    end
    WorkflowService.expects(:enqueue).never

    run_tool(InternalTools::TrackerTransitionIssue, issue: "ENG-1", status: "Doing")

    origin = TriggerEvent.sole.data["origin"]
    assert_equal [ true, run.id, [ workflow.id ] ], origin.values_at("attributed", "workflow_run_id", "chain")
  end

  test "an issue-created webhook that overtakes the create waits for it, then is the run's own" do
    workflow, run = agent_run!
    create(:trigger_binding, project: @project, workflow: workflow, created_by: @user, event_type: "tracker.issue.created")
    subscription = create(:tracker_subscription, integration: @integration)
    @jira.before_answering(:create_issue) do
      deliver(subscription, kind: :issue_created, issue_id: @jira.issues.keys.last, revision: "1", actor: { id: "557058:ada", name: "Ada" })
    end
    WorkflowService.expects(:enqueue).never

    created = run_tool(InternalTools::TrackerCreateIssue, type: "Task", title: "Flaky login")

    assert_equal 0, TriggerEvent.count
    perform_enqueued_jobs(only: Trackers::ProcessDeliveryJob)
    event = TriggerEvent.sole
    assert_equal [ created["id"], true, run.id ], [ event.data.dig("issue", "id"), *event.data["origin"].values_at("attributed", "workflow_run_id") ]
  end

  test "tracker_list_users finds who an issue can be assigned to" do
    users = run_tool(InternalTools::TrackerListUsers, query: "ada lovelace")["users"]

    assert_equal [ { "id" => "557058:ada", "name" => "Ada Lovelace" } ], users
  end
  test "a file shown only in restricted comments is listed as restricted and never fetched" do
    stub_container_runtime
    public_file = @jira.add_file("10100", name: "trace.log", bytes: "trace")
    hidden = @jira.add_file("10100", name: "dump.png", bytes: "png", content_type: "image/png")
    @jira.add_comment_by("10100", body: "see !dump.png|thumbnail!", restricted: true)
    @jira.add_comment_by("10100", body: "full log: [^trace.log]")

    files = run_tool(InternalTools::TrackerListAttachments, issue: "ENG-1")["attachments"]
    downloaded = run_tool(InternalTools::TrackerDownloadAttachments, issue: "ENG-1")["files"]

    assert_equal [ [ public_file, false ], [ hidden, true ] ], files.map { |f| f.values_at("id", "restricted") }
    assert_equal({ "kind" => "comment", "id" => @jira.comments_by_issue["10100"].last[:id] }, files.first["location"])
    assert_equal [ %w[copied], %w[skipped restricted] ], downloaded.map { |f| f.values_at("status", "reason").compact }
    assert_equal [ public_file ], @jira.calls_to(:download_attachment).pluck(:id)
  end

  test "files go up one by one and the comment shows them in wiki markup" do
    result = run_tool(InternalTools::TrackerAttachFiles, issue: "ENG-1", comment: "Screens",
                                                         files: [ { content: "png", filename: "shot.png" }, { content: "%PDF", filename: "spec.pdf" } ])

    assert_equal %w[shot.png spec.pdf], @jira.uploads.pluck(:name)
    assert_equal "Screens\n\n!shot.png|thumbnail!\n\n[^spec.pdf]", @jira.comments_by_issue["10100"].last[:body]
    assert_equal result["comment"]["id"], TrackerOperation.find_by!(operation: "attach_files").result_ref
  end

  test "a site with attachments switched off refuses each file and posts nothing" do
    @jira.attachments_enabled = false

    result = run_tool(InternalTools::TrackerAttachFiles, issue: "ENG-1", comment: "x", files: [ { content: "a", filename: "a.txt" } ])

    assert_equal [ [ "refused", "attachments_disabled" ] ], result["files"].map { |f| f.values_at("status", "reason") }
    assert_nil result["comment"]
    assert_empty @jira.comments_by_issue["10100"]
  end
end
