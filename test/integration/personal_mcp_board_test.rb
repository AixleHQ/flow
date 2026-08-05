# frozen_string_literal: true

require "test_helper"

# Personal MCP board tools: session-less, user-token, project-scoped through
# the same board policies the UI uses.
class PersonalMCPBoardTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
    @todo = create(:board_column, board: @board, name: "To Do", position: 1)
    @done = create(:board_column, board: @board, name: "Done", position: 2)
    @task = create(:board_task, board: @board, board_column: @todo, title: "First task")
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

  def payload(body)
    JSON.parse(body.dig("result", "content").first["text"])
  end

  def tool_error?(body) = body.dig("result", "isError")

  test "list_board_columns returns the project's columns" do
    cols = payload(call_tool("list_board_columns", { project_id: @project.id }))["columns"]
    assert_equal %w[To\ Do Done], cols.map { |c| c["name"] }
  end

  test "list_board_tasks lists tasks and filters by column" do
    all = payload(call_tool("list_board_tasks", { project_id: @project.id }))["tasks"]
    assert_includes all.map { |t| t["title"] }, "First task"

    filtered = payload(call_tool("list_board_tasks", { project_id: @project.id, column_id: @done.id }))["tasks"]
    assert_empty filtered
  end

  test "get_board_task returns full detail with snake_case keys" do
    task = payload(call_tool("get_board_task", { project_id: @project.id, task_id: @task.id }))
    assert_equal "First task", task["title"]
    # The resource camelizes for the frontend; a tool payload must not.
    assert_equal @todo.id, task["board_column_id"]
    assert task.key?("comments_count")
    assert_empty task.keys.grep(/[A-Z]/)
  end

  test "create_board_task creates a task in the target column" do
    body = call_tool("create_board_task",
                     { project_id: @project.id, column_id: @todo.id, title: "New", description: "d" })
    created = payload(body)
    assert_not tool_error?(body)
    assert BoardTask.exists?(created["id"])
    assert_equal "To Do", created["column"]
  end

  test "update_board_task updates fields" do
    body = call_tool("update_board_task", { project_id: @project.id, task_id: @task.id, priority: "high" })
    assert_not tool_error?(body)
    assert_equal "high", @task.reload.priority
  end

  test "update_board_task assigns and then unassigns a project member" do
    member = create(:user, company: @company)
    @project.add_collaborator(member)

    assigned = call_tool("update_board_task",
                         { project_id: @project.id, task_id: @task.id, assignee_id: member.id })
    assert_not tool_error?(assigned)
    assert_equal member.id, @task.reload.assignee_id
    assert_equal member.id, payload(assigned)["assignee_id"]
    detail = payload(call_tool("get_board_task", { project_id: @project.id, task_id: @task.id }))
    assert_equal member.id, detail["assignee_id"]

    cleared = call_tool("update_board_task",
                        { project_id: @project.id, task_id: @task.id, unassign: true })
    assert_not tool_error?(cleared)
    assert_nil @task.reload.assignee_id
  end

  test "update_board_task refuses an assignee who cannot reach the project" do
    outsider = create(:user, :with_company)

    body = call_tool("update_board_task",
                     { project_id: @project.id, task_id: @task.id, assignee_id: outsider.id })
    assert tool_error?(body)
    assert_match(/member of the project/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
    assert_nil @task.reload.assignee_id
  end

  test "update_board_task rejects assignee_id together with unassign" do
    member = create(:user, company: @company)
    @project.add_collaborator(member)
    @task.update!(assignee: member)

    body = call_tool("update_board_task",
                     { project_id: @project.id, task_id: @task.id, assignee_id: member.id, unassign: true })
    assert tool_error?(body)
    assert_match(/either assignee_id or unassign/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
    assert_equal member.id, @task.reload.assignee_id
  end

  test "list_project_members returns assignable users with roles" do
    member = create(:user, company: @company)
    @project.add_collaborator(member)

    members = payload(call_tool("list_project_members", { project_id: @project.id }))["members"]
    assert_equal [ "owner", "collaborator" ], members.map { |m| m["role"] }
    assert_equal [ @user.id, member.id ], members.map { |m| m["id"] }
  end

  test "list_project_members omits a collaborator whose company membership was revoked" do
    member = create(:user, company: @company)
    @project.add_collaborator(member)
    member.company_memberships.find_by(company: @company).revoke!

    members = payload(call_tool("list_project_members", { project_id: @project.id }))["members"]
    assert_equal [ @user.id ], members.map { |m| m["id"] }
  end

  test "move_board_task moves to another column" do
    body = call_tool("move_board_task", { project_id: @project.id, task_id: @task.id, column_id: @done.id })
    assert_not tool_error?(body)
    assert_equal @done.id, @task.reload.board_column_id
  end

  test "add_board_comment and list_board_comments round-trip" do
    body = call_tool("add_board_comment", { project_id: @project.id, task_id: @task.id, body: "hello" })
    assert_not tool_error?(body)
    comments = payload(call_tool("list_board_comments", { project_id: @project.id, task_id: @task.id }))["comments"]
    assert_equal "hello", comments.first["body"]
    assert_equal "human", comments.first["author_type"]
  end

  test "board column create / update / reorder / delete" do
    created = payload(call_tool("create_board_column", { project_id: @project.id, name: "Review", purpose: "PRs" }))
    cid = created["id"]
    assert BoardColumn.exists?(cid)

    assert_not tool_error?(call_tool("update_board_column", { project_id: @project.id, column_id: cid, name: "In Review" }))
    assert_equal "In Review", BoardColumn.find(cid).name

    reordered = call_tool("reorder_board_columns",
                          { project_id: @project.id, column_ids: [ @done.id, cid, @todo.id ] })
    assert_not tool_error?(reordered)
    assert_equal [ @done.id, cid, @todo.id ], @board.board_columns.order(:position).pluck(:id)

    assert_not tool_error?(call_tool("delete_board_column", { project_id: @project.id, column_id: cid }))
    assert_not BoardColumn.exists?(cid)
  end

  test "delete_board_column is rejected when the column has tasks" do
    body = call_tool("delete_board_column", { project_id: @project.id, column_id: @todo.id })
    assert tool_error?(body)
    assert_match(/has tasks/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
  end

  test "column management requires project admin (owner)" do
    member = create(:user, company: @company)
    @project.add_collaborator(member)
    mtoken = member.regenerate_mcp_token!

    body = call_tool("create_board_column", { project_id: @project.id, name: "X" }, token: mtoken)
    assert tool_error?(body)
    assert_match(/not allowed/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
  end

  test "unknown / inaccessible project is not found" do
    other = create(:user, :with_company)
    other_project = create(:project, company: other.companies.first, owner: other)

    body = call_tool("list_board_columns", { project_id: other_project.id })
    assert tool_error?(body)
    assert_match(/not found/i, body.dig("result", "content").first["text"])
  end

  test "a read-only viewer can read but not create tasks" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    read = call_tool("list_board_tasks", { project_id: @project.id }, token: vtoken)
    assert_not tool_error?(read)

    write = call_tool("create_board_task",
                      { project_id: @project.id, column_id: @todo.id, title: "nope" }, token: vtoken)
    assert tool_error?(write)
    assert_match(/not allowed/i, write.dig("result", "content").first["text"])
  end
end
