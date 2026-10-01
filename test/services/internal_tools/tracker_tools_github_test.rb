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
end
