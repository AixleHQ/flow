# frozen_string_literal: true

require "test_helper"

# get_step_run: the per-step diagnostic view behind get_workflow_run's bare
# states — error fields plus the terminal session that actually died.
class PersonalMCPStepRunsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @step = create(:step, workflow: @workflow, name: "Install BMAD", position: 2)
    @run = @workflow.runs.create!(project: @project, user: @user, state: "running")
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

  def failed_session(context_metadata: {}, error_message: "container exited with code 1")
    create(:terminal_session, :failed, user: @user, project: @project,
           session_type: "workflow_step", error_message: error_message,
           context_metadata: context_metadata)
  end

  test "get_step_run surfaces the error fields get_workflow_run leaves out" do
    step_run = @run.step_runs.create!(
      step: @step, state: "failed", retry_count: 2,
      started_at: 2.minutes.ago, completed_at: 1.minute.ago,
      error_category: "container_start", error_message: "BMAD install failed",
      error_history: [ { "attempt" => 1, "message" => "timeout" } ],
      step_note: "needs a bigger image"
    )

    # get_workflow_run knows only that it failed.
    listed = payload(call_tool("get_workflow_run", { project_id: @project.id, run_id: @run.id }))["step_runs"]
    assert_equal [ "failed" ], listed.map { |sr| sr["state"] }
    assert_not listed.first.key?("error_message")

    detail = payload(call_tool("get_step_run", { project_id: @project.id, step_run_id: step_run.id }))
    assert_equal "failed", detail["state"]
    assert_equal "Install BMAD", detail["step"]
    assert_equal 2, detail["step_position"]
    assert_equal 2, detail["retry_count"]
    assert_equal "container_start", detail["error_category"]
    assert_equal "BMAD install failed", detail["error_message"]
    assert_equal [ { "attempt" => 1, "message" => "timeout" } ], detail["error_history"]
    assert_equal 0, detail["error_history_omitted"]
    assert_equal "needs a bigger image", detail["step_note"]
    assert_nil detail["terminal_session"]
  end

  test "get_step_run reports the terminal session's context_metadata" do
    session = failed_session(context_metadata: { "bmad_install_status" => "failed",
                                                 "bmad_install_error" => "npm registry unreachable" })
    step_run = @run.step_runs.create!(step: @step, state: "failed", terminal_session: session,
                                      error_message: "step session failed")

    detail = payload(call_tool("get_step_run", { project_id: @project.id, step_run_id: step_run.id }))
    assert_equal session.id, detail["terminal_session"]["id"]
    assert_equal "failed", detail["terminal_session"]["state"]
    assert_equal "container exited with code 1", detail["terminal_session"]["error_message"]
    assert_equal "failed", detail["terminal_session"]["context_metadata"]["bmad_install_status"]
    assert_equal "npm registry unreachable", detail["terminal_session"]["context_metadata"]["bmad_install_error"]
  end

  test "get_step_run truncates an error message big enough to be a log dump" do
    step_run = @run.step_runs.create!(step: @step, state: "failed", error_message: "x" * 9000)

    detail = payload(call_tool("get_step_run", { project_id: @project.id, step_run_id: step_run.id }))
    assert_operator detail["error_message"].length, :<, 9000
    assert_match(/truncated, 9000 chars total/, detail["error_message"])
  end

  test "get_step_run keeps only the most recent error_history entries" do
    history = (1..15).map { |i| { "attempt" => i } }
    step_run = @run.step_runs.create!(step: @step, state: "failed", error_history: history)

    detail = payload(call_tool("get_step_run", { project_id: @project.id, step_run_id: step_run.id }))
    assert_equal 10, detail["error_history"].size
    assert_equal 6, detail["error_history"].first["attempt"]
    assert_equal 5, detail["error_history_omitted"]
  end

  test "get_step_run cannot reach another company's step run" do
    other = create(:user, :with_company)
    other_project = create(:project, company: other.companies.first, owner: other)
    other_workflow = create(:workflow, scope: other_project)
    other_run = other_workflow.runs.create!(project: other_project, user: other, state: "running")
    other_step_run = other_run.step_runs.create!(step: create(:step, workflow: other_workflow), state: "failed",
                                                 error_message: "not yours")

    stolen = call_tool("get_step_run", { project_id: @project.id, step_run_id: other_step_run.id })
    assert error?(stolen)
    assert_match(/not found/i, stolen.dig("result", "content").map { |c| c["text"] }.join(" "))

    denied = call_tool("get_step_run", { project_id: other_project.id, step_run_id: other_step_run.id })
    assert error?(denied)
    assert_match(/not found/i, denied.dig("result", "content").first["text"])
  end

  test "a read-only viewer can read a step run" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    step_run = @run.step_runs.create!(step: @step, state: "failed", error_message: "boom")

    detail = payload(call_tool("get_step_run", { project_id: @project.id, step_run_id: step_run.id },
                               token: viewer.regenerate_mcp_token!))
    assert_equal "boom", detail["error_message"]
  end
end
