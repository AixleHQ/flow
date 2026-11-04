# frozen_string_literal: true

require "test_helper"

# Feature events are reported from the models, so a change made through the
# Flow MCP server reports the same event as one made in the UI, marked by where
# it came from; and a change nobody made in person reports nothing.
class AnalyticsTrackingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    enable_analytics!
    @user = create(:user, :with_company, analytics_consent: "granted")
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @todo = create(:board_column, board: @board, name: "To Do", position: 1)
  end

  def call_tool(name, args = {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@user.regenerate_mcp_token!}" }
  end

  test "a board task created through the Flow MCP server arrives with via=mcp" do
    call_tool("create_board_task", { project_id: @project.id, title: "Ship it", column_id: @todo.id })

    event = analytics_event("board_task_created")
    assert_equal @user.id.to_s, event["distinct_id"]
    assert_equal({ "via" => "mcp", "project_id" => @project.id, "company_id" => @company.id },
                 event["properties"].slice("via", "project_id", "company_id"))
    assert_not_includes event.to_json, "Ship it"
  end

  test "a change no person made reports nothing" do
    create(:board_task, board: @board, board_column: @todo, title: "From a trigger")

    assert_empty analytics_events
  end

  test "a run reports its start and, on failure, why, charged to whoever started it" do
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow, position: 3)
    run = create(:workflow_run, workflow: workflow, project: @project, user: @user, source: "web")

    started = analytics_event("workflow_run_started")
    assert_equal({ "trigger" => "manual", "is_first" => true }, started["properties"].slice("trigger", "is_first"))

    create(:step_run, workflow_run: run, step: step, state: "failed", error_category: "quota_exceeded")
    run.update!(state: "failed", completed_at: Time.current)

    assert_equal "failed", analytics_event("workflow_run_finished")["properties"]["status"]
    assert_equal({ "failed_step_index" => 3, "reason" => "provider_quota" },
                 analytics_event("workflow_run_failed")["properties"].slice("failed_step_index", "reason"))
  end

  test "a run that neither a person nor a trigger author answers for reports nothing" do
    workflow = create(:workflow, scope: @project)
    run = create(:workflow_run, workflow: workflow, project: @project, user: nil, source: "trigger")

    assert_empty analytics_events
    assert_nil run.user
  end

  test "a company event with no person in the request goes to whoever signed the company up" do
    @company.update!(created_by: @user)
    other_admin = create(:user, company: @company, membership_role: "admin")

    assert_equal @user, @company.analytics_owner

    @user.company_memberships.find_by(company: @company).revoke!
    assert_equal other_admin, @company.reload.analytics_owner
  end
end
