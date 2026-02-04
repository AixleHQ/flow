# frozen_string_literal: true

require "test_helper"

class MCPServerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "creates valid custom MCP server with company scope" do
    server = MCPServer.new(
      name: "context7",
      display_name: "Context7",
      url: "https://mcp.context7.io",
      transport: "sse",
      kind: "custom",
      scope: @company
    )

    assert server.valid?
    assert server.save
  end

  test "creates valid custom MCP server with project scope" do
    server = MCPServer.new(
      name: "tavily",
      display_name: "Tavily Search",
      url: "https://mcp.tavily.com",
      transport: "sse",
      kind: "custom",
      scope: @project
    )

    assert server.valid?
    assert server.save
  end

  test "validates name format" do
    # Name starting with number is invalid
    server = MCPServer.new(
      display_name: "Test",
      url: "https://example.com",
      kind: "custom",
      scope: @company
    )
    # Bypass sanitizer by setting raw attribute
    server.write_attribute(:name, "123-invalid")

    assert_not server.valid?
    assert_includes server.errors[:name], "must start with letter, use lowercase letters, numbers, dashes, underscores"
  end

  test "validates name uniqueness within scope" do
    MCPServer.create!(
      name: "context7",
      display_name: "Context7",
      url: "https://mcp.context7.io",
      kind: "custom",
      scope: @company
    )

    duplicate = MCPServer.new(
      name: "context7",
      display_name: "Context7 Duplicate",
      url: "https://mcp2.context7.io",
      kind: "custom",
      scope: @company
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "already exists in this scope"
  end

  test "allows same name in different scopes" do
    MCPServer.create!(
      name: "context7",
      display_name: "Context7 Company",
      url: "https://mcp.context7.io",
      kind: "custom",
      scope: @company
    )

    project_server = MCPServer.new(
      name: "context7",
      display_name: "Context7 Project",
      url: "https://mcp2.context7.io",
      kind: "custom",
      scope: @project
    )

    assert project_server.valid?
  end

  test "custom server requires scope" do
    server = MCPServer.new(
      name: "test",
      display_name: "Test",
      url: "https://example.com",
      kind: "custom"
    )

    assert_not server.valid?
    assert_includes server.errors[:scope], "can't be blank"
  end

  test "custom server requires url" do
    server = MCPServer.new(
      name: "test",
      display_name: "Test",
      kind: "custom",
      scope: @company
    )

    assert_not server.valid?
    assert_includes server.errors[:url], "can't be blank"
  end

  test "internal server does not require scope or url" do
    server = MCPServer.new(
      name: "palad-tools",
      display_name: "Palad Tools",
      kind: "internal"
    )

    assert server.valid?
  end

  test "scopes return correct servers" do
    company_server = MCPServer.create!(
      name: "company-server",
      display_name: "Company Server",
      url: "https://company.example.com",
      kind: "custom",
      scope: @company
    )

    project_server = MCPServer.create!(
      name: "project-server",
      display_name: "Project Server",
      url: "https://project.example.com",
      kind: "custom",
      scope: @project
    )

    assert_includes MCPServer.for_company(@company), company_server
    assert_not_includes MCPServer.for_company(@company), project_server

    assert_includes MCPServer.for_project(@project), project_server
    assert_not_includes MCPServer.for_project(@project), company_server
  end

  test "merged_for_project returns company and project servers" do
    company_server = MCPServer.create!(
      name: "company-server",
      display_name: "Company Server",
      url: "https://company.example.com",
      kind: "custom",
      scope: @company
    )

    project_server = MCPServer.create!(
      name: "project-server",
      display_name: "Project Server",
      url: "https://project.example.com",
      kind: "custom",
      scope: @project
    )

    merged = MCPServer.merged_for_project(@project)

    assert_includes merged, company_server
    assert_includes merged, project_server
  end

  test "merged_for_project shows project server overriding company server" do
    MCPServer.create!(
      name: "shared-name",
      display_name: "Company Version",
      url: "https://company.example.com",
      kind: "custom",
      scope: @company
    )

    project_server = MCPServer.create!(
      name: "shared-name",
      display_name: "Project Version",
      url: "https://project.example.com",
      kind: "custom",
      scope: @project
    )

    merged = MCPServer.merged_for_project(@project)

    # Should include project server with override indicator
    matching = merged.find { |s| s.name == "shared-name" }
    assert_not_nil matching
    assert_equal "overrides_company", matching.scope_indicator
    assert_equal project_server.id, matching.id
  end

  test "enabled scope filters correctly" do
    enabled = MCPServer.create!(
      name: "enabled-server",
      display_name: "Enabled",
      url: "https://enabled.example.com",
      kind: "custom",
      scope: @company,
      enabled: true
    )

    disabled = MCPServer.create!(
      name: "disabled-server",
      display_name: "Disabled",
      url: "https://disabled.example.com",
      kind: "custom",
      scope: @company,
      enabled: false
    )

    assert_includes MCPServer.enabled, enabled
    assert_not_includes MCPServer.enabled, disabled
  end
end
