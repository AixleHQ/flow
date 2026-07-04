# frozen_string_literal: true

require "test_helper"

# Personal MCP: config items (secret-safe), repositories, assets, project
# settings and project creation.
class PersonalMCPProjectConfigTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :admin, company: create(:company))
    @company = @user.company
    @project = create(:project, company: @company, owner: @user)
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

  test "config item CRUD masks secret values" do
    created = payload(call_tool("create_config_item",
                                { project_id: @project.id, name: "API_KEY", value: "s3cr3t", item_type: "secret" }))
    id = created["id"]

    listed = payload(call_tool("list_config_items", { project_id: @project.id }))["config_items"]
    row = listed.find { |c| c["id"] == id }
    assert_equal "secret", row["item_type"]
    refute_equal "s3cr3t", row["value"] # masked, never the plaintext

    assert_not error?(call_tool("update_config_item", { project_id: @project.id, config_item_id: id, description: "key" }))
    assert_not error?(call_tool("delete_config_item", { project_id: @project.id, config_item_id: id }))
    assert_not ConfigItem.exists?(id)
  end

  test "repository CRUD (company admin)" do
    integration = create(:integration, company: @company, project: @project, provider: :github,
                         status: :active, connected_by: @user)
    created = payload(call_tool("create_repository",
                                { project_id: @project.id, full_name: "org/repo",
                                  clone_url: "https://github.com/org/repo.git", integration_id: integration.id }))
    id = created["id"]
    assert_not error?(call_tool("update_repository", { project_id: @project.id, repository_id: id, purpose: "docs" }))
    assert_not error?(call_tool("delete_repository", { project_id: @project.id, repository_id: id }))
    assert_not Repository.exists?(id)
  end

  test "list_assets returns project assets" do
    assert_not error?(call_tool("list_assets", { project_id: @project.id }))
  end

  test "update_project_settings changes the project" do
    assert_not error?(call_tool("update_project_settings", { project_id: @project.id, description: "new desc" }))
    assert_equal "new desc", @project.reload.description
  end

  test "create_project makes a project owned by the user" do
    body = call_tool("create_project", { name: "Fresh", description: "d" })
    created = payload(body)
    project = Project.find(created["id"])
    assert_equal @user, project.owner
    assert_equal @company, project.company
  end

  test "a non-admin cannot manage repositories" do
    member = create(:user, company: @company)
    @project.add_collaborator(member)
    mtoken = member.regenerate_mcp_token!

    body = call_tool("create_repository", { project_id: @project.id, full_name: "o/r" }, token: mtoken)
    assert error?(body)
    assert_match(/not allowed/i, body.dig("result", "content").map { |c| c["text"] }.join(" "))
  end
end
