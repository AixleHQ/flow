# frozen_string_literal: true

require "test_helper"

class PersonalMCPWorkflowsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
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

  test "list_workflows lists project-visible workflows" do
    names = payload(call_tool("list_workflows", { project_id: @project.id }))["workflows"].map { |w| w["name"] }
    assert_includes names, @workflow.name
  end

  test "create_workflow then get_workflow and create_workflow_step" do
    created = payload(call_tool("create_workflow", { project_id: @project.id, name: "Built by MCP" }))
    wf_id = created["id"]
    assert Workflow.exists?(wf_id)

    step_body = call_tool("create_workflow_step",
                          { project_id: @project.id, workflow_id: wf_id, name: "Step 1", instructions: "do it" })
    assert_not error?(step_body)

    detail = payload(call_tool("get_workflow", { project_id: @project.id, workflow_id: wf_id }))
    assert_equal 1, detail["steps_count"]
    assert_equal "Step 1", detail["steps"].first["name"]
  end

  test "update_workflow edits name, description and base resources, and get_workflow reports them" do
    tool = create(:tool, scope: @project)
    skill = create(:skill, scope: @project)
    server = create(:mcp_server, scope: @project)

    updated = payload(call_tool("update_workflow",
                                { project_id: @project.id, workflow_id: @workflow.id,
                                  name: "Renamed", description: "new description",
                                  base_tool_ids: [ tool.id ], base_skill_ids: [ skill.id ],
                                  base_mcp_server_ids: [ server.id ] }))
    assert_equal "Renamed", updated["name"]
    assert_includes updated["updated_fields"], "base_tool_ids"

    detail = payload(call_tool("get_workflow", { project_id: @project.id, workflow_id: @workflow.id }))
    assert_equal "Renamed", detail["name"]
    assert_equal "new description", detail["description"]
    assert_equal [ tool.id ], detail["base_tool_ids"]
    assert_equal [ skill.id ], detail["base_skill_ids"]
    assert_equal [ server.id ], detail["base_mcp_server_ids"]
    assert_nil detail["published_at"]

    nothing = call_tool("update_workflow", { project_id: @project.id, workflow_id: @workflow.id })
    assert error?(nothing)
    assert_match(/no fields/i, text(nothing))
  end

  test "get_workflow_step returns full instructions and wiring while get_workflow truncates and flags" do
    long = "x" * 900
    agent = create(:agent, scope: @project)
    tool = create(:tool, scope: @project)
    step = create(:step, workflow: @workflow, instructions: long, agent: agent,
                         tool_ids: [ tool.id ], bmad_enabled: true, mount_repositories: false, max_retries: 2)
    create(:sub_step, step: step, name: "check A", instructions: long)

    listed = payload(call_tool("get_workflow", { project_id: @project.id, workflow_id: @workflow.id }))["steps"].first
    assert_equal 500, listed["instructions"].length
    assert listed["instructions_truncated"]
    assert listed["sub_steps"].first["instructions_truncated"]

    full = payload(call_tool("get_workflow_step",
                             { project_id: @project.id, workflow_id: @workflow.id, step_id: step.id }))
    assert_equal long, full["instructions"]
    assert_equal long, full["sub_steps"].first["instructions"]
    assert_equal agent.id, full.dig("agent", "id")
    assert_equal [ tool.id ], full["tool_ids"]
    assert full["bmad_enabled"]
    assert_equal false, full["mount_repositories"] # rubocop:disable Minitest/RefuteFalse
    assert_equal 2, full["max_retries"]
    assert_equal "fail", full["on_failure"]
    assert_equal "never", full["skip_policy"]
  end

  test "create_workflow_step wires agent, tools, skills, servers, deps and flags in one call" do
    first = payload(call_tool("create_workflow_step",
                              { project_id: @project.id, workflow_id: @workflow.id, name: "S1" }))
    agent = create(:agent, scope: @project)
    tool = create(:tool, scope: @project)
    skill = create(:skill, scope: @project)
    server = create(:mcp_server, scope: @project)

    created = payload(call_tool("create_workflow_step",
                                { project_id: @project.id, workflow_id: @workflow.id, name: "S2",
                                  instructions: "do it", agent_id: agent.id,
                                  tool_ids: [ tool.id ], skill_ids: [ skill.id ],
                                  mcp_server_ids: [ server.id ], depends_on_step_ids: [ first["id"] ],
                                  bmad_enabled: true, allow_non_interactive: true }))

    step = Step.find(created["id"])
    assert_equal agent.id, step.agent_id
    assert_equal [ tool.id ], step.tool_ids
    assert_equal [ skill.id ], step.skill_ids
    assert_equal [ server.id ], step.mcp_server_ids
    assert_equal [ first["id"] ], step.depends_on_step_ids
    assert step.bmad_enabled
    assert step.allow_non_interactive
  end

  test "update_workflow_step toggles bmad_enabled and allow_non_interactive" do
    step = create(:step, workflow: @workflow)

    body = call_tool("update_workflow_step",
                     { project_id: @project.id, workflow_id: @workflow.id, step_id: step.id,
                       bmad_enabled: true, allow_non_interactive: true })
    assert_not error?(body)
    assert_includes payload(body)["updated_fields"], "bmad_enabled"

    step.reload
    assert step.bmad_enabled
    assert step.allow_non_interactive
  end

  test "duplicate_workflow copies steps and reports what needs manual setup" do
    step = create(:step, workflow: @workflow, name: "S1", instructions: "work")
    create(:sub_step, step: step, name: "check A")

    copy = payload(call_tool("duplicate_workflow",
                             { project_id: @project.id, workflow_id: @workflow.id, name: "Copy of it" }))
    assert_not_equal @workflow.id, copy["id"]
    assert_equal "Copy of it", copy["name"]
    assert_equal @project.id, copy["project_id"]
    assert_equal @workflow.id, copy["source_workflow_id"]
    assert_equal 1, copy["steps_count"]
    assert copy["needs_setup"].any? { |m| m.match?(/not copied/i) }

    duplicated_step = Workflow.find(copy["id"]).steps.not_deleted.first
    assert_equal "S1", duplicated_step.name
    assert_equal [ "check A" ], duplicated_step.sub_steps.active.map(&:name)
  end

  test "duplicate_workflow copies into another reachable project and refuses an unreachable one" do
    create(:step, workflow: @workflow, name: "S1")
    target = create(:project, company: @company, owner: @user)

    copied = payload(call_tool("duplicate_workflow",
                               { project_id: @project.id, workflow_id: @workflow.id,
                                 target_project_id: target.id }))
    assert_equal target.id, copied["project_id"]
    assert_equal target.id, Workflow.find(copied["id"]).scope_id

    outsider = create(:user, :with_company)
    outsider_project = create(:project, company: outsider.companies.first, owner: outsider)
    denied = call_tool("duplicate_workflow",
                       { project_id: @project.id, workflow_id: @workflow.id,
                         target_project_id: outsider_project.id })
    assert error?(denied)
    assert_match(/not found/i, text(denied))
  end

  test "trigger_workflow starts a run and list/get_workflow_run report it" do
    run_obj = @workflow.runs.create!(project: @project, user: @user, state: "pending")
    WorkflowService.stubs(:start).returns(run_obj)

    body = call_tool("trigger_workflow", { project_id: @project.id, workflow_id: @workflow.id })
    assert_not error?(body)
    assert_equal run_obj.id, payload(body)["run_id"]

    runs = payload(call_tool("list_workflow_runs", { project_id: @project.id }))["runs"]
    assert_includes runs.map { |r| r["id"] }, run_obj.id

    detail = payload(call_tool("get_workflow_run", { project_id: @project.id, run_id: run_obj.id }))
    assert_equal "pending", detail["state"]
  end

  test "sub-steps, update, reorder and delete round-trip through workflow authoring tools" do
    s1 = payload(call_tool("create_workflow_step", { project_id: @project.id, workflow_id: @workflow.id, name: "S1" }))
    s2 = payload(call_tool("create_workflow_step", { project_id: @project.id, workflow_id: @workflow.id, name: "S2" }))

    sub = call_tool("create_sub_step",
                    { project_id: @project.id, workflow_id: @workflow.id, step_id: s1["id"], name: "check A" })
    assert_not error?(sub)

    upd = call_tool("update_workflow_step",
                    { project_id: @project.id, workflow_id: @workflow.id, step_id: s2["id"],
                      depends_on_step_ids: [ s1["id"] ] })
    assert_not error?(upd)

    reordered = call_tool("reorder_workflow_steps",
                          { project_id: @project.id, workflow_id: @workflow.id, step_ids: [ s2["id"], s1["id"] ] })
    assert_not error?(reordered)

    # s1 has a dependent (s2) → delete rejected
    blocked = call_tool("delete_workflow_step", { project_id: @project.id, workflow_id: @workflow.id, step_id: s1["id"] })
    assert error?(blocked)
    assert_match(/depend on it/i, blocked.dig("result", "content").map { |c| c["text"] }.join(" "))

    ok = call_tool("delete_workflow_step", { project_id: @project.id, workflow_id: @workflow.id, step_id: s2["id"] })
    assert_not error?(ok)
  end

  test "cancel_workflow_run delegates to WorkflowService.cancel" do
    run = @workflow.runs.create!(project: @project, user: @user, state: "running")
    WorkflowService.expects(:cancel).with(run: run)

    body = call_tool("cancel_workflow_run", { project_id: @project.id, run_id: run.id })
    assert_not error?(body)
  end

  test "run control: approve / retry / skip delegate to WorkflowService" do
    run = @workflow.runs.create!(project: @project, user: @user, state: "running")
    sr = run.step_runs.create!(step: @workflow.steps.create!(name: "S", position: 1), state: "pending")
    # sr is the run's only pending step_run, so the real WorkflowRun#current_step_run
    # (state IN pending/running/waiting_input, newest) resolves to it on the reloaded
    # run the tool looks up — no stubbing of the class under test needed (R5/R6).

    WorkflowService.expects(:approve_step).with(step_run: sr)
    assert_not error?(call_tool("approve_step_run", { project_id: @project.id, run_id: run.id }))

    WorkflowService.expects(:skip_step).with(step_run: sr, reason: "n/a")
    assert_not error?(call_tool("skip_step_run", { project_id: @project.id, run_id: run.id, reason: "n/a" }))
  end

  test "list_agents lists project agents" do
    assert_not error?(call_tool("list_agents", { project_id: @project.id }))
  end

  test "delete_workflow soft-deletes and cannot cross into another project" do
    other = create(:user, :with_company)
    other_project = create(:project, company: other.companies.first, owner: other)
    other_wf = create(:workflow, scope: other_project)

    denied = call_tool("delete_workflow", { project_id: @project.id, workflow_id: other_wf.id })
    assert error?(denied)
    assert_match(/not found/i, denied.dig("result", "content").first["text"])

    ok = call_tool("delete_workflow", { project_id: @project.id, workflow_id: @workflow.id })
    assert_not error?(ok)
    assert @workflow.reload.deleted_at.present?
  end

  test "a read-only viewer can list but not create workflows" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    assert_not error?(call_tool("list_workflows", { project_id: @project.id }, token: vtoken))

    write = call_tool("create_workflow", { project_id: @project.id, name: "nope" }, token: vtoken)
    assert error?(write)
    assert_match(/not allowed/i, write.dig("result", "content").first["text"])
  end
end
