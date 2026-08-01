# frozen_string_literal: true

require "test_helper"

class Web::Company::Projects::ConnectorsControllerTest < ActionDispatch::IntegrationTest
  REGISTRY_URL = "https://registry.modelcontextprotocol.io/v0.1/servers"

  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  def mirrored_connector(fixture = "remote_http_secret_header")
    manifest = MCP::ConnectorManifest.normalize(JSON.parse(file_fixture("mcp_registry/#{fixture}.json").read))
    create(:connector, name: manifest["name"], title: manifest["title"], description: manifest["description"],
                       version: manifest["version"], manifest: manifest)
  end

  # Installing now captures a tool baseline, so the connector's own MCP endpoint
  # answers too. Best-effort by design: a server that does not respond must not
  # block the install.
  def stub_probe(url, tools: [ { name: "search", description: "Search", inputSchema: { "type" => "object" } } ])
    stub_request(:post, url).to_return do |request|
      body =
        if JSON.parse(request.body)["method"] == "tools/list"
          { jsonrpc: "2.0", id: 1, result: { tools: tools } }
        else
          { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-06-18", capabilities: { tools: {} },
                                             serverInfo: { name: "x", version: "1" } } }
        end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  def stub_live_fetch(connector, fixture)
    stub_request(:get, "#{REGISTRY_URL}/#{CGI.escape(connector.name)}/versions/#{connector.version}")
      .to_return(status: 200, body: file_fixture("mcp_registry/#{fixture}.json").read,
                 headers: { "Content-Type" => "application/json" })
  end

  # ------------------------------------------------------------------- create

  test "create installs a connector as a project MCP server" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_probe("https://api.adadvisor.ai/mcp")
    target_id = connector.manifest["targets"].first["id"]

    assert_difference -> { @project.mcp_servers.count }, 1 do
      post company_project_connectors_path(@project),
           params: { connector_name: connector.name, target_id: target_id, values: { "Authorization" => "sig" } }
    end

    assert_redirected_to company_project_mcp_servers_path(@project)
    server = @project.mcp_servers.last

    assert_equal connector.name, server.connector_name
    assert_equal({ "Authorization" => "sig" }, server.headers)
  end

  test "create re-fetches the manifest live rather than trusting the mirror" do
    connector = mirrored_connector
    stub = stub_live_fetch(connector, "remote_http_secret_header")
    stub_probe("https://api.adadvisor.ai/mcp")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"] }

    assert_requested stub
  end

  test "create falls back to the mirrored manifest when the registry is unreachable" do
    connector = mirrored_connector
    stub_request(:get, /#{Regexp.escape(REGISTRY_URL)}/).to_return(status: 503)
    stub_probe("https://api.adadvisor.ai/mcp")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"] }

    assert_redirected_to company_project_mcp_servers_path(@project)
    assert_match(/registry unreachable/, flash[:notice])
    assert_equal 1, @project.mcp_servers.count
  end

  test "create ignores values the manifest does not declare" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_probe("https://api.adadvisor.ai/mcp")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"],
                   values: { "Authorization" => "sig", "X-Smuggled" => "evil" } }

    assert_equal({ "Authorization" => "sig" }, @project.mcp_servers.last.headers)
  end

  test "create drops nested structures from submitted values" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_probe("https://api.adadvisor.ai/mcp")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"],
                   values: { "Authorization" => { "nested" => "payload" } } }

    assert_empty @project.mcp_servers.last.headers, "only scalars may reach the wire"
  end

  test "create preserves registry input keys verbatim" do
    connector = mirrored_connector("packages_pypi_and_mcpb")
    stub_live_fetch(connector, "packages_pypi_and_mcpb")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name,
                   target_id: connector.manifest["targets"].find { |t| t["supported"] }["id"],
                   values: { "LINEAR_PAT" => "lin_api_x" } }

    assert_equal({ "LINEAR_PAT" => "lin_api_x" }, @project.mcp_servers.last.env,
                 "the global key-underscoring must not rewrite registry input names")
  end

  test "create rejects a target the connector does not offer" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: "remote:http:https://evil.example.com/mcp" }

    assert_equal 0, @project.mcp_servers.count
    assert_match(/no longer offered/, flash[:alert])
  end

  test "create reports an unknown connector without raising" do
    post company_project_connectors_path(@project), params: { connector_name: "io.github.nobody/nothing" }

    assert_redirected_to company_project_mcp_servers_path(@project)
    assert_equal "Connector not found", flash[:alert]
  end

  test "installing the same connector twice does not collide on name" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_probe("https://api.adadvisor.ai/mcp")
    target_id = connector.manifest["targets"].first["id"]

    2.times do
      post company_project_connectors_path(@project), params: { connector_name: connector.name, target_id: target_id }
    end

    assert_equal [ "AdAdvisor MCP Server", "AdAdvisor MCP Server (2)" ], @project.mcp_servers.order(:id).pluck(:name)
  end

  # A registry manifest declares a server's INPUTS, never its auth model, so a
  # hosted connector arrives looking exactly like a public one. The install asks
  # the server instead of guessing.
  test "create detects that a server requires sign-in and says so" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_request(:post, "https://api.adadvisor.ai/mcp")
      .to_return(status: 401, headers: { "WWW-Authenticate" => "Bearer" })

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"] }

    server = @project.mcp_servers.last

    assert_predicate server, :auth_type_oauth?
    assert_match(/requires sign-in/, flash[:notice])
  end

  test "create leaves a public server unauthenticated rather than demanding a connection" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_probe("https://api.adadvisor.ai/mcp")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"] }

    server = @project.mcp_servers.last

    assert_predicate server, :auth_type_none?
    assert_no_match(/requires sign-in/, flash[:notice])
  end

  test "create records a tool baseline so later changes are detectable" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_probe("https://api.adadvisor.ai/mcp")

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"] }

    server = @project.mcp_servers.last

    assert_predicate server, :tool_baseline?
    assert_equal [ "search" ], server.tool_snapshot["tools"].map { |t| t["name"] }
    assert_not server.tool_drift?
  end

  test "an unprobeable server still installs, with the missing baseline left visible" do
    connector = mirrored_connector
    stub_live_fetch(connector, "remote_http_secret_header")
    stub_request(:post, "https://api.adadvisor.ai/mcp").to_timeout

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"] }

    server = @project.mcp_servers.last

    assert_predicate server, :persisted?
    assert_not server.tool_baseline?, "a missing baseline must not be faked as a clean one"
  end

  # --------------------------------------------------------------- permissions

  test "a viewer may not install" do
    viewer = create(:user, :onboarding_completed, company: @company, membership_role: :viewer,
                           password: AuthHelper::TEST_PASSWORD)
    create(:project_collaborator, project: @project, user: viewer)
    connector = mirrored_connector
    sign_in_as(viewer)

    post company_project_connectors_path(@project),
         params: { connector_name: connector.name, target_id: connector.manifest["targets"].first["id"] }

    assert_equal 0, @project.mcp_servers.count
  end
end
