# frozen_string_literal: true

require "test_helper"

class MCPServerTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "rejects company scope for custom MCP server" do
    server = MCPServer.new(
      name: "context7",
      url: "https://mcp.context7.io",
      transport: "sse",
      kind: "custom",
      scope: @company
    )

    assert_not server.valid?
    assert_includes server.errors[:scope_type], "must be a project"
  end

  test "creates valid custom MCP server with project scope" do
    server = MCPServer.new(
      name: "tavily",
      url: "https://mcp.tavily.com",
      transport: "sse",
      kind: "custom",
      scope: @project
    )

    assert server.valid?
    assert server.save
  end

  test "allows a free-form name with no format constraint" do
    # The lowercase protocol identifier is derived at config time (config_key), so
    # the name itself accepts spaces, capitals and punctuation verbatim.
    server = MCPServer.new(
      name: "My Fancy Server!",
      url: "https://example.com",
      kind: "custom",
      scope: @project
    )

    assert server.valid?, server.errors.full_messages.to_sentence
    assert server.save
    assert_equal "My Fancy Server!", server.reload.name
  end

  test "config_key derives a lowercase protocol identifier from the name" do
    assert_equal "context7", MCPServer.config_key_for("Context7")
    assert_equal "my_fancy_server", MCPServer.config_key_for("My Fancy Server!")
    assert_equal "playwright_browser", MCPServer.config_key_for("Playwright  Browser")
    # Names already within [a-z0-9_-] (e.g. existing slugs) pass through unchanged.
    assert_equal "aixle-tools", MCPServer.config_key_for("aixle-tools")

    server = MCPServer.new(name: "My Fancy Server!")
    assert_equal "my_fancy_server", server.config_key
  end

  test "validates name uniqueness within scope" do
    MCPServer.create!(
      name: "context7",
      url: "https://mcp.context7.io",
      kind: "custom",
      scope: @project
    )

    duplicate = MCPServer.new(
      name: "context7",
      url: "https://mcp2.context7.io",
      kind: "custom",
      scope: @project
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "already exists in this scope"
  end

  test "allows same name in different scopes" do
    other_project = create(:project, company: @company, owner: @user)

    MCPServer.create!(
      name: "context7",
      url: "https://mcp.context7.io",
      kind: "custom",
      scope: other_project
    )

    project_server = MCPServer.new(
      name: "context7",
      url: "https://mcp2.context7.io",
      kind: "custom",
      scope: @project
    )

    assert project_server.valid?
  end

  test "custom server requires scope" do
    server = MCPServer.new(
      name: "test",
      url: "https://example.com",
      kind: "custom"
    )

    assert_not server.valid?
    assert_includes server.errors[:scope], "can't be blank"
  end

  test "custom server requires url" do
    server = MCPServer.new(
      name: "test",
      kind: "custom",
      scope: @project
    )

    assert_not server.valid?
    assert_includes server.errors[:url], "can't be blank"
  end

  test "internal server does not require scope or url" do
    server = MCPServer.new(
      name: "aixle-tools",
      kind: "internal"
    )

    assert server.valid?
  end

  test "for_project scope returns only that project's servers" do
    other_project = create(:project, company: @company, owner: @user)

    project_server = MCPServer.create!(
      name: "project-server",
      url: "https://project.example.com",
      kind: "custom",
      scope: @project
    )

    other_server = MCPServer.create!(
      name: "other-server",
      url: "https://other.example.com",
      kind: "custom",
      scope: other_project
    )

    assert_includes MCPServer.for_project(@project), project_server
    assert_not_includes MCPServer.for_project(@project), other_server
  end

  test "visible_for_project returns internal and project servers only" do
    internal_server = MCPServer.create!(
      name: "aixle-tools",
      kind: "internal"
    )

    project_server = MCPServer.create!(
      name: "project-server",
      url: "https://project.example.com",
      kind: "custom",
      scope: @project
    )

    other_project = create(:project, company: @company, owner: @user)
    other_server = MCPServer.create!(
      name: "other-server",
      url: "https://other.example.com",
      kind: "custom",
      scope: other_project
    )

    result = MCPServer.visible_for_project(@project)

    assert_includes result, internal_server
    assert_includes result, project_server
    assert_not_includes result, other_server
  end

  test "visible_for_project returns ActiveRecord::Relation" do
    result = MCPServer.visible_for_project(@project)
    assert_kind_of ActiveRecord::Relation, result
  end

  # ====================================================================
  # SSRF Protection
  # ====================================================================

  test "rejects private IPv4 addresses" do
    %w[http://10.0.0.1/mcp http://172.16.0.1/mcp http://192.168.1.1/mcp].each do |private_url|
      server = MCPServer.new(
        name: "test-ssrf", url: private_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{private_url} to be rejected"
      assert_includes server.errors[:url], "cannot point to private or internal network addresses"
    end
  end

  test "rejects loopback addresses" do
    %w[http://127.0.0.1/mcp http://127.0.0.2:8080/mcp].each do |loopback_url|
      server = MCPServer.new(
        name: "test-ssrf", url: loopback_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{loopback_url} to be rejected"
      assert_includes server.errors[:url], "cannot point to private or internal network addresses"
    end
  end

  test "rejects link-local addresses (cloud metadata)" do
    server = MCPServer.new(
      name: "test-ssrf", url: "http://169.254.169.254/latest/meta-data/",
      kind: "custom", scope: @project
    )
    assert_not server.valid?
    assert_includes server.errors[:url], "cannot point to private or internal network addresses"
  end

  test "rejects blocked hostnames" do
    %w[http://localhost:3000/mcp http://metadata.google.internal/mcp http://metadata.goog/mcp].each do |blocked_url|
      server = MCPServer.new(
        name: "test-ssrf", url: blocked_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{blocked_url} to be rejected"
      assert server.errors[:url].any?, "Expected url error for #{blocked_url}"
    end
  end

  test "rejects non-http schemes" do
    %w[ftp://example.com/mcp file:///etc/passwd javascript:alert(1)].each do |bad_url|
      server = MCPServer.new(
        name: "test-ssrf", url: bad_url,
        kind: "custom", scope: @project
      )
      assert_not server.valid?, "Expected #{bad_url} to be rejected"
      assert server.errors[:url].any?, "Expected url error for #{bad_url}"
    end
  end

  test "allows valid public URLs" do
    %w[https://mcp.context7.io https://api.tavily.com/mcp http://mcp.example.com:8080/sse].each do |good_url|
      server = MCPServer.new(
        name: "test-valid", url: good_url,
        kind: "custom", scope: @project
      )
      server.valid?
      assert_empty server.errors[:url], "Expected #{good_url} to be valid, got: #{server.errors[:url]}"
    end
  end

  test "internal servers skip URL validation" do
    server = MCPServer.new(
      name: "aixle-internal", kind: "internal"
    )
    assert server.valid?
  end

  # ====================================================================
  # Scopes
  # ====================================================================

  test "enabled scope filters correctly" do
    enabled = MCPServer.create!(
      name: "enabled-server",
      url: "https://enabled.example.com",
      kind: "custom",
      scope: @project,
      enabled: true
    )

    disabled = MCPServer.create!(
      name: "disabled-server",
      url: "https://disabled.example.com",
      kind: "custom",
      scope: @project,
      enabled: false
    )

    assert_includes MCPServer.enabled, enabled
    assert_not_includes MCPServer.enabled, disabled
  end

  # ====================================================================
  # OAuth: auth_type + credential_scope (Phase 3)
  # ====================================================================

  test "auth_type defaults to none and credential_scope to shared" do
    server = MCPServer.new(
      name: "defaults",
      url: "https://mcp.example.com", kind: "custom", scope: @project
    )

    assert_equal "none", server.auth_type
    assert_equal "shared", server.credential_scope
    assert server.auth_type_none?
    assert server.credential_scope_shared?
  end

  test "auth_type predicates" do
    server = MCPServer.new

    server.auth_type = "none"
    assert server.auth_type_none?
    assert_not server.auth_type_static?
    assert_not server.auth_type_oauth?

    server.auth_type = "static"
    assert server.auth_type_static?
    assert_not server.auth_type_none?
    assert_not server.auth_type_oauth?

    server.auth_type = "oauth"
    assert server.auth_type_oauth?
    assert_not server.auth_type_none?
    assert_not server.auth_type_static?
  end

  test "credential_scope predicates" do
    server = MCPServer.new

    server.credential_scope = "shared"
    assert server.credential_scope_shared?
    assert_not server.credential_scope_per_user?

    server.credential_scope = "per_user"
    assert server.credential_scope_per_user?
    assert_not server.credential_scope_shared?
  end

  test "oauth? convenience predicate mirrors auth_type_oauth?" do
    server = MCPServer.new
    server.auth_type = "static"
    assert_not server.oauth?
    server.auth_type = "oauth"
    assert server.oauth?
  end

  test "rejects unknown auth_type / credential_scope values" do
    server = MCPServer.new(
      name: "bad-enum", url: "https://mcp.example.com",
      kind: "custom", scope: @project, auth_type: "bogus", credential_scope: "nobody"
    )

    assert_not server.valid?
    assert server.errors[:auth_type].any?
    assert server.errors[:credential_scope].any?
  end

  test "with_auth_type scope filters by auth_type" do
    oauth_server = MCPServer.create!(
      name: "oauth-srv", url: "https://oauth.example.com",
      kind: "custom", scope: @project, auth_type: "oauth"
    )
    static_server = MCPServer.create!(
      name: "static-srv", url: "https://static.example.com",
      kind: "custom", scope: @project, auth_type: "static"
    )

    result = MCPServer.with_auth_type(:oauth)
    assert_includes result, oauth_server
    assert_not_includes result, static_server
  end

  test "with_credential_scope scope filters by credential_scope" do
    per_user = MCPServer.create!(
      name: "per-user-srv", url: "https://pu.example.com",
      kind: "custom", scope: @project, auth_type: "oauth", credential_scope: "per_user"
    )
    shared = MCPServer.create!(
      name: "shared-srv", url: "https://shared.example.com",
      kind: "custom", scope: @project, auth_type: "oauth", credential_scope: "shared"
    )

    result = MCPServer.with_credential_scope(:per_user)
    assert_includes result, per_user
    assert_not_includes result, shared
  end

  test "oauth server requires https url" do
    server = MCPServer.new(
      name: "oauth-http", url: "http://mcp.example.com",
      kind: "custom", scope: @project, auth_type: "oauth"
    )

    assert_not server.valid?
    assert_includes server.errors[:url], "must use https"
  end

  test "oauth server accepts https url" do
    server = MCPServer.new(
      name: "oauth-https", url: "https://mcp.example.com",
      kind: "custom", scope: @project, auth_type: "oauth"
    )

    server.valid?
    assert_empty server.errors[:url]
  end

  test "static server does not require https url" do
    server = MCPServer.new(
      name: "static-http", url: "http://mcp.example.com:8080/sse",
      kind: "custom", scope: @project, auth_type: "static"
    )

    server.valid?
    assert_empty server.errors[:url]
  end

  # The two shapes a stdio launch line arrives in. A catalog install fills `args`
  # (MCP::ConnectorAttributes); the install form fills only `command`.
  test "launch_args takes the stored args of a catalog install" do
    server = MCPServer.new(
      name: "remote-fs", kind: "custom", scope: @project, transport: "stdio",
      command: "npx", args: [ "-y", "remote-filesystem-mcp-server@0.1.2" ]
    )

    assert_equal "npx", server.command_executable
    assert_equal [ "-y", "remote-filesystem-mcp-server@0.1.2" ], server.launch_args
  end

  test "launch_args splits the command line of a hand-written server" do
    server = MCPServer.new(
      name: "playwright", kind: "custom", scope: @project, transport: "stdio",
      command: "npx @playwright/mcp --headless"
    )

    assert_equal "npx", server.command_executable
    assert_equal [ "@playwright/mcp", "--headless" ], server.launch_args
  end

  test "launch_args is empty for a bare command with no arguments" do
    server = MCPServer.new(
      name: "bare", kind: "custom", scope: @project, transport: "stdio", command: "my-mcp"
    )

    assert_empty server.launch_args
  end
end
