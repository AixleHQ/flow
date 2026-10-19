# frozen_string_literal: true

require "test_helper"

# The tracker tools over a GitHub Projects connection, through the real provider.
class InternalTools::TrackerToolsGithubTest < ActiveSupport::TestCase
  setup do
    @github = stub_github_projects!
    @integration = create(:integration, :github_projects, :active)
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

  test "the agent moves a card by column name, and the board's echo of it is the run's own change" do
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    create(:step_run, workflow_run: run, step: create(:step, :non_interactive, workflow: workflow), terminal_session: @session.reload)
    create(:trigger_binding, project: @project, workflow: workflow, created_by: @user, event_type: "tracker.issue.status_changed")
    WorkflowService.expects(:enqueue).never

    moved = run_tool(InternalTools::TrackerTransitionIssue, issue: "https://github.com/acme-corp/app/issues/1", status: "In Progress")

    assert_equal [ "acme-corp/app#1", "In Progress" ], [ moved["key"], moved.dig("status", "name") ]
    notification = Trackers::Notification.build(kind: :issue_updated, scope_id: FakeGithub::ProjectsApi::ROADMAP, issue_id: "I_kwDOissue1",
                                                changes: [ { field: "status", from: "Ready for AI", to: "In Progress" } ],
                                                actor: { name: "aixle-flow[bot]" }, occurred_at: "2026-10-01T10:02:00Z")
    Trackers::EventPipeline.new(@integration).process(notification)

    origin = TriggerEvent.sole.data["origin"]
    assert_equal [ true, run.id, [ workflow.id ] ], origin.values_at("attributed", "workflow_run_id", "chain")
  end

  test "describe and search reach the board through the tracker the project has" do
    statuses = run_tool(InternalTools::TrackerDescribe)["statuses"]
    issues = run_tool(InternalTools::TrackerSearchIssues, status: "Ready for AI")["issues"]

    assert_equal [ "Todo", "Ready for AI", "In Progress", "Done" ], statuses.pluck("name")
    assert_equal [ "acme-corp/app#1" ], issues.pluck("key")
  end
  test "a person's image comes in through its signed address; their PDF is listed as unavailable" do
    stub_container_runtime
    image = "https://github.com/user-attachments/assets/1b2c3d4e-0000-4000-8000-000000000001"
    pdf = "https://github.com/user-attachments/files/123/spec.pdf"
    @github.set_body("I_kwDOissue1", "Broken: ![screen](#{image})\nSpec: [spec.pdf](#{pdf})")
    @github.add_person_image("I_kwDOissue1", url: image, bytes: "png")

    files = run_tool(InternalTools::TrackerListAttachments, issue: "acme-corp/app#1")["attachments"]
    downloaded = run_tool(InternalTools::TrackerDownloadAttachments, issue: "acme-corp/app#1")["files"]

    assert_equal [ [ "screen.png", true ], [ "spec.pdf", false ] ], files.map { |f| f.values_at("name", "available") }
    assert_equal [ [ "copied", nil ], [ "skipped", "unavailable" ] ], downloaded.map { |f| f.values_at("status", "reason") }
    assert_match(/jwt=signed/, @github.calls_to(:download_signed).sole[:url])
  end

  test "a file goes into the issue's repository and the comment shows it from the commit" do
    run_tool(InternalTools::TrackerAttachFiles, issue: "acme-corp/app#1", files: [ { content: "png", filename: "after.png" } ])
    again = run_tool(InternalTools::TrackerAttachFiles, issue: "acme-corp/app#1", comment: "Same file",
                                                        files: [ { content: "png", filename: "after.png" } ])

    stored = @github.stored["acme-corp/app#1"].sole
    body = @github.comments_by_content["I_kwDOissue1"].first[:body]
    assert_equal "refs/aixle/attachments/1/#{Digest::SHA256.hexdigest('png')[0, 16]}", stored[:ref]
    assert_equal "Files from Aixle:\n\n![after.png](https://github.com/acme-corp/app/blob/#{stored[:commit]}/after.png?raw=true)", body
    assert_equal [ "already_on_issue" ], again["files"].pluck("status")
  end

  test "a file the repository refuses stays on the run's task and the issue links to it" do
    workflow = create(:workflow, scope: @project)
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: task)
    create(:step_run, workflow_run: run, step: create(:step, :non_interactive, workflow: workflow), terminal_session: @session.reload)
    @github.refuse_storage = true

    result = run_tool(InternalTools::TrackerAttachFiles, issue: "acme-corp/app#1", files: [ { content: "log", filename: "run.log" } ])

    assert_equal [ "linked" ], result["files"].pluck("status")
    assert_equal [ "run.log", "agent" ], task.task_assets.sole.values_at(:name, :source)
    assert_match %r{\[run.log\]\(https?://[^)]+/board\?n=#{task.number}\) \(in Aixle\)}, @github.comments_by_content["I_kwDOissue1"].first[:body]
  end
end
