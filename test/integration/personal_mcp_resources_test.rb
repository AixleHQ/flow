# frozen_string_literal: true

require "test_helper"

class PersonalMCPResourcesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
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

  test "list_integrations returns project-visible integrations with status" do
    create(:integration, company: @company, project: @project, provider: :slack,
                         status: :active, connected_by: @user)

    rows = payload(call_tool("list_integrations", { project_id: @project.id }))["integrations"]
    slack = rows.find { |i| i["provider"] == "slack" }
    assert_equal "active", slack["status"]
  end

  test "get_integration_setup_url returns the project integrations page URL, no credentials" do
    body = call_tool("get_integration_setup_url", { project_id: @project.id, provider: "slack" })
    data = payload(body)
    assert_match %r{/company/projects/#{@project.id}/integrations}, data["setup_url"]
    assert_match(/slack/i, data["instructions"])
    refute_includes data.keys, "credentials"
  end

  test "list_project_tools lists visible tools" do
    Tools::Reconciler.run!
    create(:tool, scope: @project, name: "my_linter", docker_image: "l:1")

    names = payload(call_tool("list_project_tools", { project_id: @project.id }))["tools"].map { |t| t["name"] }
    assert_includes names, "my_linter"
  end

  test "list_skills and list_mcp_servers answer for the project" do
    assert_not error?(call_tool("list_skills", { project_id: @project.id }))
    assert_not error?(call_tool("list_mcp_servers", { project_id: @project.id }))
  end

  test "another company's project is not found" do
    other = create(:user, :with_company)
    other_project = create(:project, company: other.company, owner: other)

    body = call_tool("list_integrations", { project_id: other_project.id })
    assert error?(body)
    assert_match(/not found/i, body.dig("result", "content").first["text"])
  end
end
