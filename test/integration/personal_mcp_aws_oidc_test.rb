# frozen_string_literal: true

require "test_helper"

# Personal MCP: the AWS roles a workflow or a step can attach.
class PersonalMCPAwsOidcTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :admin, company: create(:company))
    @company = @user.companies.first
    @project = create(:project, company: @company, owner: @user)
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

  test "lists the integration's roles with the ids a step attaches" do
    integration = create(:integration, :aws_oidc, company: @company, project: @project)
    role = create(:aws_oidc_role, integration: integration, name: "prod-diag")

    with_feature(:aws_oidc, true) do
      result = payload(call_tool("list_aws_oidc_roles", { project_id: @project.id }))

      assert result["enabled"]
      assert result["connected"]
      assert_equal AwsOidc::Issuer.url(integration), result["issuer_url"]
      assert_equal [ { "id" => role.id, "name" => "prod-diag", "role_arn" => role.role_arn,
                       "account_id" => "123456789012", "region" => "eu-west-1",
                       "session_duration_seconds" => 3600 } ], result["roles"]
    end
  end

  test "a disconnected integration still lists its roles and says it is not connected" do
    integration = create(:integration, :aws_oidc, company: @company, project: @project, status: :inactive)
    create(:aws_oidc_role, integration: integration)

    with_feature(:aws_oidc, true) do
      result = payload(call_tool("list_aws_oidc_roles", { project_id: @project.id }))

      assert_not result["connected"]
      assert_equal 1, result["roles"].size
    end
  end

  test "without the flag there is nothing to attach" do
    integration = create(:integration, :aws_oidc, company: @company, project: @project)
    create(:aws_oidc_role, integration: integration)

    with_feature(:aws_oidc, false) do
      result = payload(call_tool("list_aws_oidc_roles", { project_id: @project.id }))

      assert_not result["enabled"]
      assert_empty result["roles"]
    end
  end

  test "a project the caller cannot reach is refused" do
    other_company = create(:company)
    other = create(:project, company: other_company, owner: create(:user, company: other_company))

    with_feature(:aws_oidc, true) do
      body = call_tool("list_aws_oidc_roles", { project_id: other.id })

      assert body.dig("result", "isError")
    end
  end
end
