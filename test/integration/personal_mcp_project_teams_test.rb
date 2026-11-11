# frozen_string_literal: true

require "test_helper"

# Personal MCP: project teams, and teams as a task's assignee and a trigger's Runs as.
class PersonalMCPProjectTeamsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create(:user, :with_company)
    @company = @owner.companies.first
    @project = create(:project, company: @company, owner: @owner)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    @workflow = create(:workflow, scope: @project)
    @anna = create(:user, company: @company, name: "Anna")
    @project.add_collaborator(@anna)
    create(:agent_credential, user: @anna, company: @company, agent_type: "kiro_cli")
    @token = @owner.regenerate_mcp_token!
  end

  def call_tool(name, args = {}, token: @token)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def error?(body) = body.dig("result", "isError")
  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")

  test "the owner creates, lists, edits and deletes a team" do
    created = call_tool("create_project_team", { project_id: @project.id, name: "Planner", strategy: "round_robin",
                                                 member_ids: [ @anna.id ] })
    assert_not error?(created), text(created)
    team_id = payload(created)["id"]
    assert_equal "round_robin", payload(created)["strategy"]

    listed = payload(call_tool("list_project_teams", { project_id: @project.id }))["teams"].sole
    assert_equal [ "Anna" ], listed["members"].map { |member| member["name"] }
    assert_equal [ "kiro_cli" ], listed["members"].sole["runtimes"].map { |runtime| runtime["agent_type"] }

    updated = call_tool("update_project_team", { project_id: @project.id, team_id: team_id, name: "Planners", member_ids: [] })
    assert_not error?(updated), text(updated)
    assert_empty payload(updated)["members"]

    deleted = call_tool("delete_project_team", { project_id: @project.id, team_id: team_id })
    assert_not error?(deleted), text(deleted)
    assert_equal 0, @project.project_teams.count
  end

  test "a collaborator may read teams but not change them" do
    create(:project_team, project: @project, name: "Planner")
    token = @anna.regenerate_mcp_token!

    assert_not error?(call_tool("list_project_teams", { project_id: @project.id }, token: token))
    denied = call_tool("create_project_team", { project_id: @project.id, name: "Mine" }, token: token)
    assert error?(denied)
    assert_match(/Not allowed/, text(denied))
  end

  test "a task is assigned to a team instead of a person, and back" do
    team = create(:project_team, project: @project)
    task = create(:board_task, board: @board, board_column: @column, assignee: @anna)

    body = call_tool("update_board_task", { project_id: @project.id, task_number: task.number, assignee_team_id: team.id })
    assert_not error?(body), text(body)
    assert_equal [ nil, team.id ], task.reload.values_at(:assignee_id, :assignee_team_id)

    call_tool("update_board_task", { project_id: @project.id, task_number: task.number, assignee_id: @anna.id })
    assert_equal [ @anna.id, nil ], task.reload.values_at(:assignee_id, :assignee_team_id)

    both = call_tool("update_board_task", { project_id: @project.id, task_number: task.number, assignee_id: @anna.id,
                                           assignee_team_id: team.id })
    assert error?(both)

    created = payload(call_tool("create_board_task", { project_id: @project.id, column_id: @column.id, title: "Plan",
                                                        assignee_team_id: team.id }))
    assert_equal team.id, created["assignee_team_id"]
  end

  test "a trigger runs as a team, set on create and cleared on update" do
    create(:step, :non_interactive, workflow: @workflow)
    team = create(:project_team, project: @project, name: "Planner")

    created = call_tool("create_workflow_trigger", { project_id: @project.id, workflow_id: @workflow.id, kind: "event",
                                                     event_type: "custom.nightly", run_as_team_id: team.id })
    assert_not error?(created), text(created)
    trigger = TriggerBinding.find(payload(created)["id"])
    assert_equal team, trigger.run_as_team
    assert_equal({ "id" => team.id, "name" => "Planner" }, payload(created)["run_as_team"])

    cleared = call_tool("update_workflow_trigger", { project_id: @project.id, workflow_id: @workflow.id, kind: "event",
                                                     trigger_id: trigger.id, run_as_team_id: 0 })
    assert_not error?(cleared), text(cleared)
    assert_nil trigger.reload.run_as_team
    assert_match(/from team Planner to #{@owner.name}/, Audit.where(auditable: trigger).last.comment)

    denied = call_tool("update_workflow_trigger", { project_id: @project.id, workflow_id: @workflow.id, kind: "event",
                                                    trigger_id: trigger.id, run_as_team_id: team.id },
                       token: @anna.regenerate_mcp_token!)
    assert error?(denied)
  end
end
