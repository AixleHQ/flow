# frozen_string_literal: true

require "test_helper"

# The tracker tools over a Linear connection, through the real provider.
class InternalTools::TrackerToolsLinearTest < ActiveSupport::TestCase
  setup do
    @linear = stub_linear!
    @integration = create(:integration, :linear, :active, dedicated_identity: false)
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

  test "the connection's teams are its trackers, and an identifier picks its team" do
    trackers = run_tool(InternalTools::TrackerList)["trackers"]
    comment = run_tool(InternalTools::TrackerAddComment, issue: "OPS-1", body: "Rotated")

    assert_equal [ [ "engineering", "linear", true ], [ "operations", "linear", false ] ],
                 trackers.map { |t| t.values_at("handle", "provider", "primary") }
    assert_equal [ "operations", "add_comment" ], [ TrackerOperation.sole.project_tracker.handle, TrackerOperation.sole.operation ]
    assert_equal "Rotated", comment["body"]
  end

  # An API key of a person acts as that person, so only the ledger tells the
  # agent's assignment from theirs.
  test "an assignment the agent made is attributed to its run though the account is a person's" do
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    create(:step_run, workflow_run: run, step: create(:step, :non_interactive, workflow: workflow), terminal_session: @session.reload)
    create(:trigger_binding, project: @project, workflow: workflow, created_by: @user, event_type: "tracker.issue.assigned")
    WorkflowService.expects(:enqueue).never

    run_tool(InternalTools::TrackerAssignIssue, issue: "ENG-1", assignee: "byron")
    notification = Trackers::Notification.build(kind: :issue_updated, scope_id: FakeLinear::Api::ENG, issue_id: FakeLinear::Api::ISSUE_1,
                                                changes: [ { field: "assignee", to_id: FakeLinear::Api::MEMBERS[1][:id], to: "Ada Byron" } ],
                                                actor: { id: FakeLinear::Api::BOT_ID, name: "Aixle Bot" }, revision: "r1")
    Trackers::EventPipeline.new(@integration).process(notification)

    event = TriggerEvent.sole
    assert_equal [ true, run.id ], event.data["origin"].values_at("attributed", "workflow_run_id")
    assert_equal "Ada Byron", event.data.dig("change", "to")
  end
end
