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

  def listed_titles(**args)
    payload(call_tool("list_board_tasks", { project_id: @project.id, **args }))["tasks"].map { |t| t["title"] }
  end

  # A task on a board in a company @user has nothing to do with.
  def foreign_task
    owner = create(:user, :with_company)
    project = create(:project, company: owner.companies.first, owner: owner)
    board = create(:board, project: project)
    column = create(:board_column, board: board, name: "To Do", position: 1)
    create(:board_task, board: board, board_column: column, title: "Not yours", assignee: owner)
  end

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

  test "list_board_tasks filters by archive state and lists both when the filter is omitted" do
    archived = create(:board_task, board: @board, board_column: @todo,
                      title: "Archived task", archived_at: Time.current)

    assert_equal [ "First task" ], listed_titles(archived: false)
    assert_equal [ archived.title ], listed_titles(archived: true)
    # An existing call carries no filter and keeps seeing everything.
    assert_equal [ "First task", archived.title ].sort, listed_titles.sort
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

  test "create_board_task can assign the task on creation" do
    member = create(:user, company: @company)
    @project.add_collaborator(member)

    created = payload(call_tool("create_board_task",
                                { project_id: @project.id, column_id: @todo.id,
                                  title: "Assigned on create", assignee_id: member.id }))
    assert_equal member.id, created["assignee_id"]
    assert_equal member.id, BoardTask.find(created["id"]).assignee_id
  end

  test "create_board_task refuses an assignee who cannot reach the project" do
    outsider = create(:user, :with_company)

    body = call_tool("create_board_task",
                     { project_id: @project.id, column_id: @todo.id, title: "Nope", assignee_id: outsider.id })
    assert tool_error?(body)
    assert_match(/member of the project/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
    assert_not BoardTask.exists?(title: "Nope")
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

  test "archive_board_task round-trips and the state shows in get_board_task" do
    archived = call_tool("archive_board_task", { project_id: @project.id, task_id: @task.id })
    assert_not tool_error?(archived)
    assert payload(archived)["archived"]
    assert @task.reload.archived_at.present?

    detail = payload(call_tool("get_board_task", { project_id: @project.id, task_id: @task.id }))
    assert detail["archived"]

    restored = call_tool("archive_board_task", { project_id: @project.id, task_id: @task.id, archived: false })
    assert_not tool_error?(restored)
    assert_equal false, payload(restored)["archived"] # rubocop:disable Minitest/RefuteFalse
    assert_nil @task.reload.archived_at

    back = payload(call_tool("get_board_task", { project_id: @project.id, task_id: @task.id }))
    assert_equal false, back["archived"] # rubocop:disable Minitest/RefuteFalse
  end

  # The round-trip above goes through archive_board_task; this pins get_board_task
  # to the persisted archived_at on its own, for both states.
  test "get_board_task exposes the persisted archive state" do
    archived = create(:board_task, board: @board, board_column: @todo,
                      title: "Archived task", archived_at: Time.current)

    active_detail = payload(call_tool("get_board_task", { project_id: @project.id, task_id: @task.id }))
    assert_includes active_detail.keys, "archived"
    assert_equal false, active_detail["archived"] # rubocop:disable Minitest/RefuteFalse

    archived_detail = payload(call_tool("get_board_task", { project_id: @project.id, task_id: archived.id }))
    assert archived_detail["archived"]
  end

  test "archive_board_task requires write access" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    body = call_tool("archive_board_task", { project_id: @project.id, task_id: @task.id }, token: vtoken)
    assert tool_error?(body)
    assert_match(/not allowed/i, body.dig("result", "content").first["text"])
    assert_nil @task.reload.archived_at
  end

  test "delete_board_task destroys the task and its comments" do
    create(:task_comment, board_task: @task, author: @user)

    body = call_tool("delete_board_task", { project_id: @project.id, task_id: @task.id })
    assert_not tool_error?(body)
    assert_equal @task.id, payload(body)["deleted_task_id"]
    assert_not BoardTask.exists?(@task.id)
    assert_empty TaskComment.where(board_task_id: @task.id)
  end

  test "delete_board_task is rejected while the task has an active workflow run" do
    create(:workflow_run, :running, project: @project, board_task: @task, user: @user)

    body = call_tool("delete_board_task", { project_id: @project.id, task_id: @task.id })
    assert tool_error?(body)
    assert_match(/active workflow runs/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
    assert BoardTask.exists?(@task.id)
  end

  test "delete_board_task requires write access" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    body = call_tool("delete_board_task", { project_id: @project.id, task_id: @task.id }, token: vtoken)
    assert tool_error?(body)
    assert_match(/not allowed/i, body.dig("result", "content").first["text"])
    assert BoardTask.exists?(@task.id)
  end

  test "delete_board_task cannot reach another company's task" do
    other = foreign_task

    body = call_tool("delete_board_task",
                     { project_id: other.board.project.id, task_id: other.id })
    assert tool_error?(body)
    assert BoardTask.exists?(other.id)
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

  test "setup_board builds the board a fresh project does not have" do
    fresh = create(:project, company: @company, owner: @user)
    assert_nil fresh.board

    created = payload(call_tool("setup_board", { project_id: fresh.id, preset: "simple_kanban" }))
    assert_equal %w[Backlog In\ Progress Done], created["columns"].map { |c| c["name"] }
    assert_equal [ 1, 2, 3 ], created["columns"].map { |c| c["position"] }
    assert_equal created["board_id"], fresh.reload.board.id

    # The rest of the board surface only works once the board exists.
    task = call_tool("create_board_task",
                     { project_id: fresh.id, column_id: created["columns"].first["id"], title: "First" })
    assert_not tool_error?(task)
  end

  test "setup_board refuses a second board and an unknown preset" do
    existing = call_tool("setup_board", { project_id: @project.id, preset: "dev_team" })
    assert tool_error?(existing)
    assert_match(/already has a board/i, existing.dig("result", "content").map { |c| c["text"] }.join(" "))
    assert_equal @board.id, @project.reload.board.id

    # An unknown preset never reaches the handler: the declared enum is
    # enforced by the MCP SDK before dispatch.
    fresh = create(:project, company: @company, owner: @user)
    unknown = call_tool("setup_board", { project_id: fresh.id, preset: "kanban_deluxe" })
    assert_match(/not one of/i, unknown.to_json)
    assert_nil fresh.reload.board
  end

  test "setup_board requires project admin (owner)" do
    fresh = create(:project, company: @company, owner: @user)
    member = create(:user, company: @company)
    fresh.add_collaborator(member)

    body = call_tool("setup_board", { project_id: fresh.id, preset: "simple_kanban" },
                     token: member.regenerate_mcp_token!)
    assert tool_error?(body)
    assert_match(/not allowed/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
    assert_nil fresh.reload.board
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

  test "create_board_column inserts at an occupied position instead of failing" do
    inserted = call_tool("create_board_column", { project_id: @project.id, name: "Review", position: 2 })
    assert_not tool_error?(inserted)
    assert_equal 2, payload(inserted)["position"]
    assert_equal [ [ "To Do", 1 ], [ "Review", 2 ], [ "Done", 3 ] ],
                 @board.board_columns.order(:position).pluck(:name, :position)

    # Inserting at the head shifts every existing column, exercising the
    # multi-row walk against the (board_id, position) unique index.
    head = call_tool("create_board_column", { project_id: @project.id, name: "Backlog", position: 1 })
    assert_not tool_error?(head)
    assert_equal [ [ "Backlog", 1 ], [ "To Do", 2 ], [ "Review", 3 ], [ "Done", 4 ] ],
                 @board.board_columns.order(:position).pluck(:name, :position)

    appended = call_tool("create_board_column", { project_id: @project.id, name: "Archive" })
    assert_equal 5, payload(appended)["position"]
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

  test "list_gates exposes a task's gates and delete_gate clears one" do
    gate = @task.gates.create!(gate_type: "github_checks_completed", creator: @user,
                               metadata: { "repo_full_name" => "acme/app", "pr_number" => 7 })

    gates = payload(call_tool("list_gates", { project_id: @project.id, task_id: @task.id }))["gates"]
    assert_equal [ gate.id ], gates.map { |g| g["id"] }
    assert_equal "github_checks_completed", gates.first["gate_type"]
    assert_equal "pending", gates.first["status"]
    assert_equal 7, gates.first["metadata"]["pr_number"]
    assert_equal @user.name, gates.first["creator"]

    detail = payload(call_tool("get_board_task", { project_id: @project.id, task_id: @task.id }))
    assert_equal [ gate.id ], detail["pending_gates"].map { |g| g["id"] }

    deleted = call_tool("delete_gate", { project_id: @project.id, gate_id: gate.id })
    assert_not tool_error?(deleted)
    assert_equal gate.id, payload(deleted)["deleted_gate_id"]
    assert_not Gate.exists?(gate.id)
    assert_empty payload(call_tool("list_gates", { project_id: @project.id, task_id: @task.id }))["gates"]
  end

  test "gate tools cannot reach another company's board" do
    other_task = foreign_task
    other_gate = other_task.gates.create!(gate_type: "github_workflow_completed", creator: other_task.assignee)

    stolen = call_tool("delete_gate", { project_id: @project.id, gate_id: other_gate.id })
    assert tool_error?(stolen)
    assert_match(/not found/i, stolen.dig("result", "content").map { |c| c["text"] }.join(" "))
    assert Gate.exists?(other_gate.id)

    listed = call_tool("list_gates", { project_id: other_task.board.project.id, task_id: other_task.id })
    assert tool_error?(listed)

    archived = call_tool("archive_board_task",
                         { project_id: other_task.board.project.id, task_id: other_task.id })
    assert tool_error?(archived)
    assert_nil other_task.reload.archived_at
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
