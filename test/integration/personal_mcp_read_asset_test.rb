# frozen_string_literal: true

require "test_helper"

# What a run produced and what sits on a card: listed by get_workflow_run and
# get_board_task, read by read_asset — the files a caller could otherwise only
# reach through the REST API or the UI.
class PersonalMCPReadAssetTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @run = @workflow.runs.create!(project: @project, user: @user, state: "completed")
    @token = @user.regenerate_mcp_token!
  end

  def call_tool(name, args = {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}" }
    response.parsed_body
  end

  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")
  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def tool_error?(body) = body.dig("result", "isError")

  def run_output(name, content, run: @run)
    create(:workflow_run_asset, workflow_run: run, name: name, file_size: content.bytesize,
                                file: WorkflowRunAssetUploader.upload(StringIO.new(content), :store))
  end

  test "get_workflow_run lists the run's outputs and read_asset returns one" do
    report = run_output("SECURITY-AUDIT.md", "# Audit\n\n15 findings.\n")

    outputs = payload(call_tool("get_workflow_run", { project_id: @project.id, run_id: @run.id }))["outputs"]
    assert_equal [ "SECURITY-AUDIT.md" ], outputs.pluck("name")
    assert_equal report.id, outputs.first["id"]

    read = payload(call_tool("read_asset", { project_id: @project.id, source: "run", run_id: @run.id,
                                             asset_id: report.id }))
    assert_equal "# Audit\n\n15 findings.\n", read["content"]
    assert_nil read["next_offset"]
  end

  test "read_asset pages through a large file without splitting a character" do
    content = "#{'a' * 9}é#{'b' * 10}"
    output = run_output("big.txt", content)

    first = payload(call_tool("read_asset", { project_id: @project.id, source: "run", run_id: @run.id,
                                              asset_id: output.id, limit: 10 }))
    assert_equal "a" * 9, first["content"]
    assert_equal 9, first["next_offset"]

    rest = payload(call_tool("read_asset", { project_id: @project.id, source: "run", run_id: @run.id,
                                             asset_id: output.id, offset: first["next_offset"], limit: 100 }))
    assert_equal "é#{'b' * 10}", rest["content"]
    assert_nil rest["next_offset"]
  end

  test "read_asset refuses a binary file with its size" do
    output = run_output("screenshot.png", "\x89PNG\r\n\x1A\n\x00\xFF".b)

    body = call_tool("read_asset", { project_id: @project.id, source: "run", run_id: @run.id, asset_id: output.id })
    assert tool_error?(body)
    assert_match(/screenshot.png is binary/, text(body))
  end

  test "read_asset does not reach another project's run output" do
    other_project = create(:project, company: @company, owner: @user)
    other_run = create(:workflow, scope: other_project).runs.create!(project: other_project, user: @user,
                                                                      state: "completed")
    foreign = run_output("secret.md", "not yours", run: other_run)

    body = call_tool("read_asset", { project_id: @project.id, source: "run", run_id: other_run.id,
                                     asset_id: foreign.id })
    assert tool_error?(body)
    assert_match(/not found/, text(body))
  end

  test "get_board_task lists attached files and read_asset returns one" do
    board = create(:board, project: @project)
    task = create(:board_task, board: board, board_column: create(:board_column, board: board))
    attachment = create(:task_asset, board_task: task, author: @user, name: "notes.md",
                                     file: TaskAssetUploader.upload(StringIO.new("task notes"), :store))

    listed = payload(call_tool("get_board_task", { project_id: @project.id, task_id: task.id }))["assets"]
    assert_equal [ [ attachment.id, "notes.md" ] ], listed.map { |a| [ a["id"], a["name"] ] }

    read = payload(call_tool("read_asset", { project_id: @project.id, source: "task", task_id: task.id,
                                             asset_id: attachment.id }))
    assert_equal "task notes", read["content"]
  end

  test "read_asset reads a project asset's latest version" do
    asset = create(:asset, scope: @project, created_by: @user)
    create(:asset_version, :with_file, asset: asset, uploaded_by: @user)

    read = payload(call_tool("read_asset", { project_id: @project.id, source: "project", asset_id: asset.id }))
    assert_equal "test file content", read["content"]
  end

  test "read_asset asks for the id its source needs" do
    body = call_tool("read_asset", { project_id: @project.id, source: "task", asset_id: 1 })
    assert tool_error?(body)
    assert_match(/task_id is required/, text(body))
  end
end
