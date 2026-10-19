# frozen_string_literal: true

require "test_helper"

# The tracker tools and the event pipeline over a GitLab connection, through
# the real provider (docs/design/gitlab-tracker.md §5).
class InternalTools::TrackerToolsGitlabTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PROJECT = FakeGitlab::TrackerApi::PROJECT

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @gitlab = stub_gitlab_tracker!
    @integration = gitlab_tracker_integration
    Trackers::Provisioning.ensure_for!(@integration)
    @project = @integration.project
    @user = create(:user, company: @project.company)
    @session = create(:terminal_session, :running, :agent_session, user: @user, project: @project,
                      mode: "non_interactive", initial_prompt: "work")
  end

  def run_tool(klass, **params)
    result = klass.new(params: params, session: @session).execute
    assert_equal 0, result[:exit_code], result[:stderr].presence || result[:stdout]
    JSON.parse(result[:stdout])
  end

  test "the board's label lists are the columns, between Open and Closed" do
    statuses = run_tool(InternalTools::TrackerDescribe)["statuses"]
    issue = run_tool(InternalTools::TrackerGetIssue, issue: "acme/app#1")["issue"]

    assert_equal [ [ "Open", "todo" ], [ "Ready for AI", "todo" ], [ "Doing", "in_progress" ], [ "Closed", "done" ] ],
                 statuses.map { |s| s.values_at("name", "category") }
    assert_equal [ "#{PROJECT}:1", "acme/app#1", "Ready for AI", [ "bug" ] ],
                 [ issue["id"], issue["key"], issue.dig("status", "name"), issue["labels"] ]
  end

  test "moving an issue swaps the list labels, and Closed closes it" do
    moved = run_tool(InternalTools::TrackerTransitionIssue, issue: "#1", status: "Doing")
    closed = run_tool(InternalTools::TrackerTransitionIssue, issue: "acme/app#1", status: "Closed")

    assert_equal "Doing", moved.dig("status", "name")
    assert_equal({ remove_labels: "Ready for AI", add_labels: "Doing" }, @gitlab.calls_to(:update_issue).first[:attributes])
    assert_equal [ "Closed", "closed" ], [ closed.dig("status", "name"), closed.dig("fields", "state") ]
    assert_equal [ "bug" ], @gitlab.stored_issues["#{PROJECT}:1"][:labels]
  end

  test "an issue of another project is refused" do
    result = InternalTools::TrackerGetIssue.new(params: { issue: "other/repo#3" }, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_match(/not in this tracker/, result[:stderr].presence || result[:stdout])
  end

  test "a comment is the service account's, and assigning takes a member's username" do
    run_tool(InternalTools::TrackerAddComment, issue: "#1", body: "On it")
    assigned = run_tool(InternalTools::TrackerAssignIssue, issue: "#1", assignee: "@ada")

    assert_equal [ "On it" ], @gitlab.notes_by_issue["#{PROJECT}:1"].pluck(:body)
    assert_equal [ "ada" ], assigned["assignees"]
  end

  test "files are the uploads the issue links to; an internal note's are restricted" do
    stub_container_runtime
    shot = @gitlab.add_upload(name: "shot.png", bytes: "png")
    secret = @gitlab.add_upload(name: "dump.txt", bytes: "s")
    @gitlab.stored_issues["#{PROJECT}:1"][:description] = "Repro: ![shot](#{shot})"
    @gitlab.add_note_by(1, body: "dump: [dump.txt](#{secret})", internal: true)

    files = run_tool(InternalTools::TrackerListAttachments, issue: "#1")["attachments"]
    downloaded = run_tool(InternalTools::TrackerDownloadAttachments, issue: "#1")["files"]

    assert_equal [ [ "shot.png", false ], [ "dump.txt", true ] ], files.map { |f| f.values_at("name", "restricted") }
    assert_equal [ [ "copied", nil ], [ "skipped", "restricted" ] ], downloaded.map { |f| f.values_at("status", "reason") }
  end

  test "a file goes up as an upload and the comment links it relatively" do
    run_tool(InternalTools::TrackerAttachFiles, issue: "#1", files: [ { content: "log", filename: "run.log" } ])

    body = @gitlab.notes_by_issue["#{PROJECT}:1"].last[:body]
    assert_match %r{\AFiles from Aixle:\n\n\[run\.log\]\(/uploads/\h{32}/run\.log\)\z}, body
  end

  test "a labelled move in GitLab is a status change, and the bot's own comment is the run's" do
    Gitlab::AppConfig.stubs(:webhooks_enabled?).returns(true)
    subscription = Trackers::Gitlab::Subscriptions.new(@integration).ensure!.first
    provider = Trackers::Provider.for(@integration)
    payload = {
      "object_kind" => "issue", "user" => { "id" => 11, "username" => "ada" },
      "object_attributes" => { "project_id" => PROJECT.to_i, "iid" => 1, "action" => "update", "state" => "opened",
                               "updated_at" => "2026-10-20T10:10:00Z" },
      "changes" => { "labels" => { "previous" => [ { "title" => "Ready for AI" } ], "current" => [ { "title" => "Doing" } ] } }
    }

    notifications = provider.parse_delivery(payload, subscription)

    assert_equal [ [ :issue_updated, "#{PROJECT}:1", [ { field: "status", from: "Ready for AI", to: "Doing" } ] ] ],
                 notifications.map { |n| [ n.kind, n.issue_id, n.changes ] }
    assert_equal [ PROJECT, subscription.callback_url(Gitlab::AppConfig.webhook_base_url) ],
                 @gitlab.hooks.values.first.values_at(:project_id, :url)
    assert provider.own_actor?(id: FakeGitlab::TrackerApi::BOT[:id], name: FakeGitlab::TrackerApi::BOT[:username])
  end

  test "a hook delivery is authentic only with its subscription's token" do
    Gitlab::AppConfig.stubs(:webhooks_enabled?).returns(true)
    subscription = Trackers::Gitlab::Subscriptions.new(@integration).ensure!.first
    provider = Trackers::Provider.for(@integration)
    request = ->(token) { Struct.new(:headers).new({ "X-Gitlab-Token" => token }) }

    assert provider.authentic_delivery?(request.call(subscription.secret), "", subscription)
    assert_not provider.authentic_delivery?(request.call("wrong"), "", subscription)
  end
end
