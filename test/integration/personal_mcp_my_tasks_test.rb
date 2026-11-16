# frozen_string_literal: true

require "test_helper"

class PersonalMCPMyTasksTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @alpha = create(:project, company: @company, owner: @user, name: "Alpha")
    @beta = create(:project, company: @company, owner: @user, name: "Beta")
    @token = @user.regenerate_mcp_token!
  end

  def call_tool(args = {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: { name: "list_my_tasks", arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}" }
    response.parsed_body
  end

  def payload(args = {})
    body = call_tool(args)
    assert_not body.dig("result", "isError"), body.dig("result", "content")&.first&.dig("text")
    JSON.parse(body.dig("result", "content").first["text"])
  end

  def error_text(args = {})
    body = call_tool(args)
    assert body.dig("result", "isError"), "expected a tool error"
    body.dig("result", "content").first["text"]
  end

  def titles_by_project(result)
    result["projects"].to_h { |group| [ group["project_name"], group["tasks"].map { |t| t["title"] } ] }
  end

  def column_on(project, name: "To Do", position: 1)
    board = Board.find_by(project: project) || create(:board, project: project)
    board.board_columns.find_by(name: name) || create(:board_column, board: board, name: name, position: position)
  end

  def task_on(project, **attrs)
    column = column_on(project)
    create(:board_task, board: column.board, board_column: column, **attrs)
  end

  test "lists tasks assigned to the caller or their team across the company's projects" do
    colleague = create(:user, :employee, company: @company)
    @alpha.add_collaborator(colleague)
    team = create(:project_team, project: @beta, name: "Backend")
    create(:project_team_member, project_team: team, user: @user)
    other_team = create(:project_team, project: @beta, name: "Design")

    mine = task_on(@alpha, title: "Mine", assignee: @user, priority: :high,
                           description: "a long brief", tags: %w[api])
    task_on(@alpha, title: "Colleague's", assignee: colleague)
    task_on(@alpha, title: "Unassigned")
    task_on(@alpha, title: "Archived", assignee: @user, archived_at: Time.current)
    task_on(@beta, title: "Team's", assignee_team: team)
    task_on(@beta, title: "Other team's", assignee_team: other_team)

    result = payload

    assert_equal({ "Alpha" => [ "Mine" ], "Beta" => [ "Team's" ] }, titles_by_project(result))
    assert_equal [ @alpha.id, @beta.id ], result["projects"].map { |g| g["project_id"] }
    assert_equal({ "number" => mine.number, "title" => "Mine", "task_type" => "not_specified",
                   "priority" => "high", "column" => "To Do", "tags" => %w[api] },
                 result["projects"].first["tasks"].first)
    assert_equal "Backend", result["projects"].last["tasks"].first["team"]
    assert_equal [ 2, false ], result.values_at("total", "has_more")
  end

  test "project_id narrows the list to one project" do
    task_on(@alpha, title: "In alpha", assignee: @user)
    task_on(@beta, title: "In beta", assignee: @user)

    assert_equal({ "Beta" => [ "In beta" ] }, titles_by_project(payload(project_id: @beta.id)))
  end

  test "leaves out a project the caller can no longer reach and refuses it by id" do
    colleague = create(:user, :employee, company: @company)
    shared = create(:project, company: @company, owner: colleague, name: "Shared")
    shared.add_collaborator(@user)
    task_on(shared, title: "Was mine", assignee: @user)
    shared.remove_collaborator(@user)

    assert_empty payload["projects"]
    assert_match(/not found/, error_text(project_id: shared.id))
  end

  test "a caller in two companies names the one to list" do
    second = create(:company)
    create(:company_membership, user: @user, company: second)
    elsewhere = create(:project, company: second, owner: @user, name: "Elsewhere")
    task_on(@alpha, title: "Here", assignee: @user)
    task_on(elsewhere, title: "There", assignee: @user)

    assert_match(/pass company_id/, error_text)
    assert_equal({ "Elsewhere" => [ "There" ] }, titles_by_project(payload(company_id: second.id)))
    assert_equal({ "Alpha" => [ "Here" ] }, titles_by_project(payload(company_id: @company.id)))
  end

  test "pages through the tasks in project, then board, order" do
    done = column_on(@alpha, name: "Done", position: 2)
    task_on(@beta, title: "Beta one", assignee: @user)
    create(:board_task, board: done.board, board_column: done, title: "Alpha done", assignee: @user)
    task_on(@alpha, title: "Alpha todo", assignee: @user)

    first_page = payload(limit: 2)
    assert_equal({ "Alpha" => [ "Alpha todo", "Alpha done" ] }, titles_by_project(first_page))
    assert_equal [ 3, true ], first_page.values_at("total", "has_more")

    last_page = payload(limit: 2, offset: 2)
    assert_equal({ "Beta" => [ "Beta one" ] }, titles_by_project(last_page))
    assert_equal false, last_page["has_more"] # rubocop:disable Minitest/RefuteFalse
  end
end
