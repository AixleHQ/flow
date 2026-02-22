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

  # ====================================================================
  # SSRF Protection
  # ====================================================================

  test "rejects private IPv4 addresses" do
    %w[http://10.0.0.1/mcp http://172.16.0.1/mcp http://192.168.1.1/mcp].each do |private_url|
      server = MCPServer.new(
        name: "test-ssrf", display_name: "Test", url: private_url,
        kind: "custom", scope: @company
      )
      assert_not server.valid?, "Expected #{private_url} to be rejected"
      assert_includes server.errors[:url], "cannot point to private or internal network addresses"
    end
  end

  test "rejects loopback addresses" do
    %w[http://127.0.0.1/mcp http://127.0.0.2:8080/mcp].each do |loopback_url|
      server = MCPServer.new(
        name: "test-ssrf", display_name: "Test", url: loopback_url,
        kind: "custom", scope: @company
      )
      assert_not server.valid?, "Expected #{loopback_url} to be rejected"
      assert_includes server.errors[:url], "cannot point to private or internal network addresses"
    end
  end

  test "rejects link-local addresses (cloud metadata)" do
    server = MCPServer.new(
      name: "test-ssrf", display_name: "Test", url: "http://169.254.169.254/latest/meta-data/",
      kind: "custom", scope: @company
    )
    assert_not server.valid?
    assert_includes server.errors[:url], "cannot point to private or internal network addresses"
  end

  test "rejects blocked hostnames" do
    %w[http://localhost:3000/mcp http://metadata.google.internal/mcp http://metadata.goog/mcp].each do |blocked_url|
      server = MCPServer.new(
        name: "test-ssrf", display_name: "Test", url: blocked_url,
        kind: "custom", scope: @company
      )
      assert_not server.valid?, "Expected #{blocked_url} to be rejected"
      assert server.errors[:url].any?, "Expected url error for #{blocked_url}"
    end
  end

  test "rejects non-http schemes" do
    %w[ftp://example.com/mcp file:///etc/passwd javascript:alert(1)].each do |bad_url|
      server = MCPServer.new(
        name: "test-ssrf", display_name: "Test", url: bad_url,
        kind: "custom", scope: @company
      )
      assert_not server.valid?, "Expected #{bad_url} to be rejected"
      assert server.errors[:url].any?, "Expected url error for #{bad_url}"
    end
  end

  test "allows valid public URLs" do
    %w[https://mcp.context7.io https://api.tavily.com/mcp http://mcp.example.com:8080/sse].each do |good_url|
      server = MCPServer.new(
        name: "test-valid", display_name: "Test", url: good_url,
        kind: "custom", scope: @company
      )
      server.valid?
      assert_empty server.errors[:url], "Expected #{good_url} to be valid, got: #{server.errors[:url]}"
    end
  end

  test "internal servers skip URL validation" do
    server = MCPServer.new(
      name: "palad-internal", display_name: "Internal", kind: "internal"
    )
    assert server.valid?
  end

  # ====================================================================
  # Scopes
  # ====================================================================

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
