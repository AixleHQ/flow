# frozen_string_literal: true

require "test_helper"

class PersonalMCPTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :employee, :onboarding_completed)
    @company = @user.companies.first
    @token = @user.regenerate_mcp_token!
    create(:tool, :system, name: "board_add_comment")
    package = Templates::Package.from_directory(Rails.root.join("test/fixtures/files/templates/dev-team-sdlc"))
    @template = CatalogTemplate.new.assign_package(package, commit_sha: "c" * 40).tap(&:save!)
  end

  def call_tool(name, args = {})
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}" }
    response.parsed_body
  end

  def payload(body) = JSON.parse(body.dig("result", "content").first["text"])
  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")

  test "search and get describe the catalog without installing anything" do
    results = payload(call_tool("search_template_catalog", { query: "delivery" }))["results"]
    assert_equal [ "acme/dev-team-sdlc" ], results.pluck("identifier")
    assert_equal({ "integrations" => [ "github" ] }, results.first["requires"].slice("integrations"))

    detail = payload(call_tool("get_template", { template: "acme/dev-team-sdlc" }))
    assert_equal [ "Backlog", "Tech Design", "Code Review", "Done" ], detail["board_columns"]
    assert_equal %w[default_branch review_language], detail["inputs"].pluck("key")
    assert detail["runs_third_party_images"]
  end

  test "a dry run returns the plan and writes nothing" do
    assert_no_difference -> { Project.count } do
      body = call_tool("install_template", { template: "acme/dev-team-sdlc", company_id: @company.id,
                                             idempotency_key: "a", dry_run: true })
      plan = payload(body)["plan"]
      assert_equal "new_project", plan["target"]
      assert plan["resolved"]
    end
  end

  test "install creates the project and never echoes the secret back" do
    body = call_tool("install_template", { template: "acme/dev-team-sdlc", company_id: @company.id, idempotency_key: "b",
                                           version: @template.version, commit_sha: @template.commit_sha,
                                           secrets: { "SENTRY_TOKEN" => "tok-secret-value" } })

    result = payload(body)
    project = Project.find(result["project_id"])
    assert_equal @user, project.owner
    assert_match %r{/company/projects/#{project.id}/template_installs/#{result['template_install_id']}\z}, result["checklist_url"]
    assert_not_includes text(body), "tok-secret-value"
  end

  test "export_template packages an installed project and refuses what it cannot carry" do
    project = Project.find(payload(call_tool("install_template", { template: "acme/dev-team-sdlc", company_id: @company.id,
                                                                    idempotency_key: "e" }))["project_id"])

    body = call_tool("export_template", { project_id: project.id, namespace: "acme", slug: "my-delivery", name: "My delivery",
                                          include_assets: true })
    assert_not body.dig("result", "isError"), text(body)
    exported = payload(body)
    assert_equal "templates/acme/my-delivery", exported["directory"]
    assert_match(/slug: my-delivery/, exported["template_yaml"])
    assert_includes exported["files"].pluck("path"), "snapshots/skills/code_review.md"

    project.mcp_servers.find_by!(name: "Sentry").update!(headers: { "X-Org" => "acme" })
    refused = call_tool("export_template", { project_id: project.id, namespace: "acme", slug: "my-delivery", name: "My delivery",
                                            include_assets: true })
    assert refused.dig("result", "isError")
    assert_match(/X-Org holds a literal value/, text(refused))
  end

  test "the publish_template prompt names the repository and the validator" do
    post "/mcp",
         params: { jsonrpc: "2.0", id: 1, method: "prompts/get", params: { name: "publish_template" } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                    "Authorization" => "Bearer #{@token}" }

    guide = response.parsed_body.dig("result", "messages", 0, "content", "text")
    assert_match(%r{AixleHQ/flow-templates}, guide)
    assert_match(/bin\/validate/, guide)
  end

  test "a stale version is refused as a tool error" do
    body = call_tool("install_template", { template: "acme/dev-team-sdlc", company_id: @company.id, idempotency_key: "c",
                                           version: @template.version + 1 })

    assert body.dig("result", "isError")
    assert_match(/changed since you opened it/, text(body))
  end
end
