# frozen_string_literal: true

require "test_helper"

# A personal MCP token reaches a company only when the sign-in that issued it
# proved a method that company accepts.
class PersonalMCPSignInPolicyTest < ActionDispatch::IntegrationTest
  setup do
    @open_company = create(:company)
    @sso_company = create(:company)
    @user = create(:user, :onboarding_completed, company: @open_company,
                          password: AuthHelper::TEST_PASSWORD, password_confirmation: AuthHelper::TEST_PASSWORD)
    create(:company_membership, user: @user, company: @sso_company, state: "active",
                                accepted_at: Time.current, onboarding_state: "completed",
                                onboarding_completed_at: Time.current)

    @sso = create(:identity_provider, company: @sso_company, kind: "oidc", name: "SSO Co")
    CompanyAuthPolicy.where(company: @sso_company).update_all(enabled: false)
    create(:company_auth_policy, company: @sso_company, identity_provider: @sso, enabled: true)

    @open_project = create(:project, company: @open_company, owner: @user)
    create(:board, project: @open_project)
    @sso_project = create(:project, company: @sso_company, owner: @user)
    create(:board, project: @sso_project)
  end

  def issue_token_from_the_profile
    post regenerate_mcp_token_profile_path
    get mcp_profile_path, headers: { "X-Inertia" => "true" }
    token = nil
    assert_inertia_props { |props| token = props[:mcp][:token] }
    token
  end

  def call_tool(token, name, args = {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{token}" }
    response.parsed_body["result"]
  end

  def error_text(result) = result["isError"] ? result["content"].first["text"] : nil

  test "a token issued under a password reaches the password company and not the SSO-only one" do
    sign_in_as(@user)
    token = issue_token_from_the_profile

    assert_nil error_text(call_tool(token, "list_board_tasks", project_id: @open_project.id))
    assert_match(/regenerate/, error_text(call_tool(token, "list_board_tasks", project_id: @sso_project.id)))

    companies = JSON.parse(call_tool(token, "list_companies")["content"].first["text"])["companies"]
    assert_equal [ @open_company.id ], companies.map { |c| c["id"] }
  end

  test "a token issued after proving the SSO company's method reaches it" do
    sign_in_as(@user)
    Auth::SessionService.record_proof(UserSession.live.find_by!(user: @user), @sso)
    token = issue_token_from_the_profile

    assert_nil error_text(call_tool(token, "list_board_tasks", project_id: @sso_project.id))
  end

  test "a token issued before proofs were recorded counts as a password sign-in" do
    token = @user.regenerate_mcp_token!

    assert_nil error_text(call_tool(token, "list_board_tasks", project_id: @open_project.id))
    assert_match(/regenerate/, error_text(call_tool(token, "list_board_tasks", project_id: @sso_project.id)))
  end
end
