# frozen_string_literal: true

require "test_helper"

# Personal MCP workflow-trigger CRUD: the one surface over ColumnWorkflowBinding
# (kind=column) and TriggerBinding (slack / schedule / webhook / event).
class PersonalMCPTriggersTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @workflow = create(:workflow, scope: @project)
    @token = @user.regenerate_mcp_token!
  end

  def call_tool(name, args = {}, token: @token)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def error?(body) = body.dig("result", "isError")
  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")

  def column_trigger!(mode: :auto, cooldown: 5)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: @workflow,
                                  trigger_mode: mode, cooldown_seconds: cooldown)
  end

  def event_trigger!(**attrs)
    create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user,
                             event_type: "slack.message", **attrs)
  end

  test "list_workflow_triggers reports column and event triggers together" do
    column_trigger!
    event_trigger!(name: "standup")

    triggers = payload(call_tool("list_workflow_triggers",
                                 { project_id: @project.id, workflow_id: @workflow.id }))["triggers"]

    assert_equal %w[column slack], triggers.map { |t| t["kind"] }.sort
    column = triggers.find { |t| t["kind"] == "column" }
    assert_equal @column.id, column["board_column_id"]
    assert_equal @column.name, column["column_name"]
    assert_equal "standup", triggers.find { |t| t["kind"] == "slack" }["name"]
  end

  test "create_workflow_trigger binds a board column" do
    body = call_tool("create_workflow_trigger",
                     { project_id: @project.id, workflow_id: @workflow.id, kind: "column",
                       board_column_id: @column.id, trigger_mode: "auto", cooldown_seconds: 7 })

    assert_not error?(body)
    trigger = payload(body)
    assert_equal "column", trigger["kind"]
    assert_equal 7, trigger["cooldown_seconds"]
    assert_equal @column.id, ColumnWorkflowBinding.find(trigger["id"]).board_column_id
  end

  test "create_workflow_trigger creates a slack trigger with a filter predicate" do
    body = call_tool("create_workflow_trigger",
                     { project_id: @project.id, workflow_id: @workflow.id, kind: "slack",
                       name: "on mention", filter_predicate: { channel: "C123" },
                       subject_policy: "create_task", subject_column_id: @column.id })

    assert_not error?(body)
    trigger = payload(body)
    assert_equal "slack", trigger["kind"]
    assert_equal "slack.message", trigger["event_type"]
    assert_equal({ "channel" => "C123" }, trigger["filter_predicate"])
    assert_equal "create_task", trigger["subject_policy"]
    assert_equal @user.id, TriggerBinding.find(trigger["id"]).created_by_id
  end

  test "create_workflow_trigger creates a cron schedule trigger" do
    body = call_tool("create_workflow_trigger",
                     { project_id: @project.id, workflow_id: @workflow.id, kind: "schedule",
                       name: "weekday standup",
                       schedule_config: { cron: "0 9 * * 1-5", timezone: "Europe/Berlin" } })

    assert_not error?(body)
    trigger = payload(body)
    assert_equal "schedule", trigger["kind"]
    assert_equal "schedule.fired", trigger["event_type"]
    assert_equal({ "cron" => "0 9 * * 1-5", "timezone" => "Europe/Berlin" }, trigger["schedule_config"])
  end

  test "create_workflow_trigger provisions a webhook endpoint and returns its url and secret" do
    body = call_tool("create_workflow_trigger",
                     { project_id: @project.id, workflow_id: @workflow.id, kind: "webhook",
                       verification_strategy: "hmac_sha256", secret: "shh" })

    assert_not error?(body)
    trigger = payload(body)
    assert_match(/\Awebhook\./, trigger["event_type"])
    assert_match %r{/webhooks/in/wh-}, trigger["webhook_url"]
    assert_equal "shh", trigger["webhook_secret"]

    endpoint = WebhookEndpoint.find_by(slug: trigger["webhook_url"].split("/").last)
    assert_equal trigger["event_type"], endpoint.config["event_type"]
    assert_equal @project.id, endpoint.project_id
  end

  test "an off-board trigger is rejected while a step still waits on a human" do
    create(:step, workflow: @workflow, name: "Review copy", allow_non_interactive: false)

    body = call_tool("create_workflow_trigger",
                     { project_id: @project.id, workflow_id: @workflow.id, kind: "slack" })

    assert error?(body)
    assert_match(/can't run unattended/i, text(body))
    assert_match(/Review copy/, text(body))
    assert_equal 0, @workflow.trigger_bindings.count
  end

  test "a schedule trigger without a cron expression is rejected" do
    body = call_tool("create_workflow_trigger",
                     { project_id: @project.id, workflow_id: @workflow.id, kind: "schedule",
                       schedule_config: { timezone: "UTC" } })

    assert error?(body)
    assert_match(/cron/i, text(body))
    assert_equal 0, @workflow.trigger_bindings.count
  end

  test "update_workflow_trigger edits each kind and leaves omitted fields alone" do
    column = column_trigger!
    event = event_trigger!(name: "standup", cooldown_seconds: 0)

    col_body = call_tool("update_workflow_trigger",
                         { project_id: @project.id, workflow_id: @workflow.id, kind: "column",
                           trigger_id: column.id, trigger_mode: "manual", cooldown_seconds: 30 })
    assert_not error?(col_body)
    assert_equal "manual", column.reload.trigger_mode
    assert_equal 30, column.cooldown_seconds

    evt_body = call_tool("update_workflow_trigger",
                         { project_id: @project.id, workflow_id: @workflow.id, kind: "slack",
                           trigger_id: event.id, enabled: false, filter_predicate: { channel: "C9" } })
    assert_not error?(evt_body)
    event.reload
    assert_not event.enabled
    assert_equal({ "channel" => "C9" }, event.filter_predicate)
    assert_equal "standup", event.name
  end

  test "delete_workflow_trigger removes each kind" do
    column = column_trigger!
    event = event_trigger!

    assert_difference -> { ColumnWorkflowBinding.count }, -1 do
      body = call_tool("delete_workflow_trigger",
                       { project_id: @project.id, workflow_id: @workflow.id, kind: "column", trigger_id: column.id })
      assert_not error?(body)
    end

    assert_difference -> { TriggerBinding.count }, -1 do
      body = call_tool("delete_workflow_trigger",
                       { project_id: @project.id, workflow_id: @workflow.id, kind: "slack", trigger_id: event.id })
      assert_not error?(body)
    end
  end

  test "another company's workflow and triggers are unreachable" do
    outsider = create(:user, :with_company)
    other_project = create(:project, company: outsider.companies.first, owner: outsider)
    other_workflow = create(:workflow, scope: other_project)
    other_trigger = create(:trigger_binding, project: other_project, workflow: other_workflow,
                                             created_by: outsider, event_type: "slack.message")

    listed = call_tool("list_workflow_triggers", { project_id: @project.id, workflow_id: other_workflow.id })
    assert error?(listed)
    assert_match(/not found/i, text(listed))

    deleted = call_tool("delete_workflow_trigger",
                        { project_id: @project.id, workflow_id: @workflow.id,
                          kind: "slack", trigger_id: other_trigger.id })
    assert error?(deleted)
    assert TriggerBinding.exists?(other_trigger.id)
  end

  test "a read-only viewer can list triggers but not create them" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    assert_not error?(call_tool("list_workflow_triggers",
                                { project_id: @project.id, workflow_id: @workflow.id }, token: vtoken))

    write = call_tool("create_workflow_trigger",
                      { project_id: @project.id, workflow_id: @workflow.id, kind: "column",
                        board_column_id: @column.id }, token: vtoken)
    assert error?(write)
    assert_match(/not allowed/i, text(write))
  end
end
