# frozen_string_literal: true

require "test_helper"

# Personal MCP: the chat channels a company connected, and the codes that connect one.
class PersonalMCPChatChannelsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @slack = create(:integration, provider: :slack, status: :active, company: @company, project: nil,
                                  settings: { "bot_name" => "aixle-flow" })
    @token = @user.regenerate_mcp_token!
  end

  def call_tool(name, args = {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}" }
    response.parsed_body
  end

  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def tool_error?(body) = body.dig("result", "isError")
  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")

  test "list_chat_channels lists the company's connected channels for chat_channel_id" do
    channel = connect_chat_channel(company: @company, integration: @slack, external_id: "C0DEPLOYS1", name: "deploys")
    connect_chat_channel(company: create(:company), external_id: "C0FOREIGN1")

    body = call_tool("list_chat_channels", { project_id: @project.id })

    assert_not tool_error?(body), text(body)
    assert_equal [ [ channel.id, "#deploys", "slack" ] ], payload(body)["channels"].map { |c| c.values_at("id", "label", "provider") }
  end

  test "create_chat_connect_code hands out a code for a trigger, and get_chat_connect_code follows it" do
    trigger = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @user, enabled: false, chat_channel: nil)

    body = call_tool("create_chat_connect_code", { project_id: @project.id, provider: "slack", trigger_id: trigger.id })

    assert_not tool_error?(body), text(body)
    code = payload(body)
    assert_equal [ "pending", "@aixle-flow", trigger.id ], code.values_at("state", "mention", "trigger_id")
    assert_match(/\Aconnect aixle-/, code["command"])

    shown = payload(call_tool("get_chat_connect_code", { project_id: @project.id, code_id: code["id"] }))
    assert_equal "pending", shown["state"]
    assert_nil shown["command"]
  end

  test "a code is refused for a messenger the company has not connected" do
    body = call_tool("create_chat_connect_code", { project_id: @project.id, provider: "teams" })

    assert tool_error?(body)
    assert_includes text(body), "Connect Microsoft Teams on the Integrations page first"
  end
end
