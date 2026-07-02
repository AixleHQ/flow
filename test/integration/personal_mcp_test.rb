# frozen_string_literal: true

require "test_helper"

# The personal (session-less) MCP server: one amcp_ token per user on the
# same /mcp endpoint, serving audience-:user registry tools with the user's
# own access level.
class PersonalMCPTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @token = @user.regenerate_mcp_token!
  end

  def rpc(method, params = {}, token: @token)
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json",
                    "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  test "token lifecycle: regenerate rotates, disable revokes" do
    old_token = @token
    new_token = @user.regenerate_mcp_token!

    rpc("tools/list", token: old_token)
    assert_response :unauthorized

    rpc("tools/list", token: new_token)
    assert_response :success

    @user.disable_mcp_token!
    rpc("tools/list", token: new_token)
    assert_response :unauthorized
  end

  test "tools/list serves the user-audience registry tools" do
    names = rpc("tools/list").dig("result", "tools").map { |t| t["name"] }

    assert_includes names, "list_companies"
    assert_includes names, "list_projects"
    # Session-audience tools never leak into the personal server.
    refute_includes names, "board_list_tasks"
    refute_includes names, "meta_create_tool"
  end

  test "personal tools are not materialized as shadow rows and stay out of session serving" do
    Tools::Reconciler.run!

    assert_not Tool.exists?(name: "list_companies")
    session = create(:terminal_session, :agent_session, user: @user, project: @project)
    assert_empty session.available_tools.map(&:name) & %w[list_companies list_projects]
  end

  test "list_companies and list_projects answer with the user's own scope" do
    other = create(:user, :with_company)
    create(:project, company: other.companies.first, owner: other)

    body = rpc("tools/call", { name: "list_companies", arguments: {} })
    companies = JSON.parse(body.dig("result", "content").first["text"])["companies"]
    assert_equal [ @company.id ], companies.map { |c| c["id"] }

    body = rpc("tools/call", { name: "list_projects", arguments: {} })
    projects = JSON.parse(body.dig("result", "content").first["text"])["projects"]
    assert_equal [ @project.id ], projects.map { |p| p["id"] }
  end

  test "the build_workflow and author_step prompts are served" do
    names = rpc("prompts/list").dig("result", "prompts").map { |p| p["name"] }
    assert_includes names, "build_workflow"
    assert_includes names, "author_step"

    wf = rpc("prompts/get", { name: "build_workflow", arguments: {} })
                   .dig("result", "messages").first.dig("content", "text")
    assert_match(/create_workflow/, wf)
    assert_match(/trigger_workflow/, wf)

    step = rpc("prompts/get", { name: "author_step", arguments: {} })
                     .dig("result", "messages").first.dig("content", "text")
    assert_match(/instructions/i, step)
    assert_match(/depends_on_step_ids/, step)
  end

  test "the last-used timestamp is touched on requests" do
    assert_nil @user.mcp_token_last_used_at

    rpc("tools/list")

    assert_not_nil @user.reload.mcp_token_last_used_at
  end
end
