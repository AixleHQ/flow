# frozen_string_literal: true

require "test_helper"

# Personal MCP resource CRUD: agents, custom tools, MCP servers, skills.
class PersonalMCPResourceCrudTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
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
  def text(body) = body.dig("result", "content").map { |c| c["text"] }.join(" ")

  test "agent create / update / delete round-trip" do
    created = payload(call_tool("create_agent", { project_id: @project.id, name: "coder", title: "Coder", persona: "writes code" }))
    id = created["id"]
    assert @project.agents.exists?(id)

    assert_not error?(call_tool("update_agent", { project_id: @project.id, agent_id: id, title: "Senior Coder" }))
    assert_equal "Senior Coder", @project.agents.find(id).title

    assert_not error?(call_tool("delete_agent", { project_id: @project.id, agent_id: id }))
    assert_not @project.agents.exists?(id)
  end

  test "custom tool create / update / delete round-trip" do
    created = payload(call_tool("create_custom_tool",
                                { project_id: @project.id, name: "linter", display_name: "Linter",
                                  docker_image: "linter:1" }))
    id = created["id"]
    assert_equal "db", created["source"]

    assert_not error?(call_tool("update_custom_tool", { project_id: @project.id, tool_id: id, enabled: false }))
    assert_not Tool.find(id).enabled

    assert_not error?(call_tool("delete_custom_tool", { project_id: @project.id, tool_id: id }))
    assert Tool.find(id).deleted?
  end

  test "custom tool create rejects a platform name collision" do
    Tools::Reconciler.run!
    body = call_tool("create_custom_tool",
                     { project_id: @project.id, name: "board_list_tasks", display_name: "x", docker_image: "i:1" })
    assert error?(body)
    assert_match(/collides|already/i, text(body))
  end

  test "MCP server create / update / delete round-trip" do
    created = payload(call_tool("create_mcp_server",
                                { project_id: @project.id, name: "ctx7", url: "https://x/mcp", transport: "http" }))
    id = created["id"]
    assert_equal "custom", created["kind"]

    assert_not error?(call_tool("update_mcp_server", { project_id: @project.id, mcp_server_id: id, enabled: false }))
    assert_not error?(call_tool("delete_mcp_server", { project_id: @project.id, mcp_server_id: id }))
    assert_not MCPServer.exists?(id)
  end

  test "get_mcp_server returns the wiring but never a header or env VALUE" do
    server = create(:mcp_server, scope: @project, name: "ctx7", url: "https://x/mcp", transport: :http,
                                 headers: { "Authorization" => "Bearer super-secret" },
                                 env: { "API_KEY" => "sk-live-1" })

    body = payload(call_tool("get_mcp_server", { project_id: @project.id, mcp_server_id: server.id }))

    assert_equal "https://x/mcp", body["url"]
    assert_equal [ "Authorization" ], body["header_names"]
    assert_equal [ "API_KEY" ], body["env_names"]
    assert_not_includes body.to_json, "super-secret"
    assert_not_includes body.to_json, "sk-live-1"
    assert_not body["from_connector"]
  end

  test "get_mcp_server reports catalog provenance and an available update" do
    connector = create(:connector, version: "2.0.0")
    server = create(:mcp_server, scope: @project, connector_name: connector.name, connector_version: "1.0.0")

    body = payload(call_tool("get_mcp_server", { project_id: @project.id, mcp_server_id: server.id }))

    assert body["from_connector"]
    assert_equal "1.0.0", body["connector_version"]
    assert_equal "2.0.0", body["catalog_version"]
    assert body["update_available"]
    assert_equal "active", body["catalog_status"]
    # Never probed here, so it must not come back claiming a verified baseline.
    assert_not body["tool_baseline_recorded"]
  end

  test "get_mcp_server refuses a server from another project" do
    other = create(:project, company: @company, owner: @user)
    foreign = create(:mcp_server, scope: other)

    body = call_tool("get_mcp_server", { project_id: @project.id, mcp_server_id: foreign.id })
    assert error?(body)
    assert_match(/not found/i, text(body))
  end

  test "search_connector_catalog browses the curated set and searches the whole mirror" do
    create(:connector, name: "com.acme/tracker", title: "Acme Tracker", featured: true)
    create(:connector, name: "io.github.someone/obscure", title: "Obscure Notes", featured: false)
    create(:connector, :deleted, name: "com.spam/pulled", title: "Pulled Entry", featured: true)

    browsed = payload(call_tool("search_connector_catalog", { project_id: @project.id }))
    names = browsed["results"].map { |r| r["name"] }
    assert_nil browsed["query"]
    assert_includes names, "com.acme/tracker"
    # Curated-only browse, and a registry-pulled entry is never discoverable.
    assert_not_includes names, "io.github.someone/obscure"
    assert_not_includes names, "com.spam/pulled"

    found = payload(call_tool("search_connector_catalog", { project_id: @project.id, query: "obscure" }))
    assert_equal [ "io.github.someone/obscure" ], found["results"].map { |r| r["name"] }
    assert found["results"].first["installable"]
  end

  test "get_connector returns install targets with their inputs and existing installs" do
    connector = create(:connector, name: "com.acme/tracker")
    connector.update!(manifest: connector.manifest.deep_merge(
      "targets" => [ connector.manifest["targets"].first.merge(
        "id" => "remote-http", "inputs" => [ { "key" => "X-Api-Key", "kind" => "header", "required" => true,
                                               "secret" => true } ]
      ) ]
    ))
    create(:mcp_server, scope: @project, name: "Tracker", connector_name: connector.name)

    body = payload(call_tool("get_connector", { project_id: @project.id, connector_name: connector.name }))

    target = body["targets"].first
    assert_equal "remote-http", target["id"]
    assert_equal "X-Api-Key", target["inputs"].first["key"]
    assert target["inputs"].first["required"]
    assert_equal [ "Tracker" ], body["already_installed"]

    missing = call_tool("get_connector", { project_id: @project.id, connector_name: "com.nope/nothing" })
    assert error?(missing)
    assert_match(/not in the catalog/i, text(missing))
  end

  test "install_connector installs the sole supported target as an MCP server" do
    connector = create(:connector, :package, name: "com.acme/cli")
    target = connector.manifest["targets"].first.merge("id" => "package-stdio")
    connector.update!(manifest: connector.manifest.merge("targets" => [ target ]))
    # Stub the registry ADAPTER, not the installer under test: the manifest is
    # re-fetched at install time and this is the seam that call reaches the network through.
    MCP::ConnectorRegistryClient.stubs(:fetch).returns(connector.manifest)

    body = payload(call_tool("install_connector", { project_id: @project.id, connector_name: connector.name }))

    server = MCPServer.find(body["id"])
    assert_equal "stdio", server.transport.to_s
    assert_equal connector.name, server.connector_name
    assert_not body["installed_from_mirror"]
  end

  test "install_connector names the choice when a connector offers several targets" do
    connector = create(:connector, name: "com.acme/both")
    connector.update!(manifest: connector.manifest.merge(
      "targets" => [
        connector.manifest["targets"].first.merge("id" => "remote-http"),
        { "kind" => "package", "transport" => "stdio", "id" => "package-stdio", "supported" => true,
          "inputs" => [] }
      ]
    ))

    body = call_tool("install_connector", { project_id: @project.id, connector_name: connector.name })
    assert error?(body)
    assert_match(/remote-http/, text(body))
    assert_match(/package-stdio/, text(body))
  end

  test "install_connector explains why an uninstallable connector cannot be installed" do
    connector = create(:connector, :uninstallable, name: "com.acme/mcpb")

    body = call_tool("install_connector", { project_id: @project.id, connector_name: connector.name })
    assert error?(body)
    assert_match(/no known runtime for mcpb/i, text(body))
  end

  test "get_registry_skill returns the SKILL.md plus the catalog audit verdict" do
    entry = create(:catalog_skill, source: "test-org/skills", slug: "fmt",
                                   audit_risk: "high", audit: { "socket" => { "risk" => "high", "score" => 0.2 } })
    SkillsRegistryService.stubs(:fetch_skill_detail)
                         .returns({ "source" => "test-org/skills", "slug" => "fmt", "name" => "fmt",
                                    "content" => "---\nname: fmt\n---\nFormat things" })

    body = payload(call_tool("get_registry_skill", { project_id: @project.id, skill_id: entry.registry_id }))

    assert_includes body["content"], "Format things"
    assert body["catalog_entry"]
    assert body["audited"]
    assert body["audit_warning"]
    assert_equal "socket", body["audit_providers"].first["provider"]
    # Reading a registry skill must not install it.
    assert_empty Skill.visible_for_project(@project).where(name: "fmt")
  end

  test "get_registry_skill reports an id the registry cannot resolve" do
    SkillsRegistryService.stubs(:fetch_skill_detail).returns(nil)

    body = call_tool("get_registry_skill", { project_id: @project.id, skill_id: "test-org/skills/ghost" })
    assert error?(body)
    assert_match(/skill not found: test-org\/skills\/ghost/i, text(body))
  end

  test "get_registry_skill names the publisher when a host has no skill index" do
    SkillsRegistryService.stubs(:fetch_skill_detail).returns(nil)

    body = call_tool("get_registry_skill", { project_id: @project.id, skill_id: "example.com/ghost" })
    assert error?(body)
    assert_match(/example\.com does not publish an installable skill index/i, text(body))
  end

  test "skill search / install / uninstall" do
    SkillsRegistryService.stubs(:search).returns([ { "id" => "s1", "name" => "fmt" } ])
    results = payload(call_tool("search_skill_registry", { project_id: @project.id, query: "fmt" }))["results"]
    assert_equal "s1", results.first["id"]

    skill = create(:skill, scope: @project)
    SkillsRegistryService.stubs(:install).returns(skill)
    installed = payload(call_tool("install_skill", { project_id: @project.id, skill_id: "s1" }))
    assert_equal skill.id, installed["id"]

    assert_not error?(call_tool("uninstall_skill", { project_id: @project.id, skill_id: skill.id }))
    assert_not Skill.exists?(skill.id)
  end

  test "a read-only viewer cannot create resources" do
    viewer = create(:user, :viewer, company: @company)
    @project.add_collaborator(viewer)
    vtoken = viewer.regenerate_mcp_token!

    body = call_tool("create_agent", { project_id: @project.id, name: "x", title: "X", persona: "p" }, token: vtoken)
    assert error?(body)
    assert_match(/not allowed/i, text(body))
  end
end
