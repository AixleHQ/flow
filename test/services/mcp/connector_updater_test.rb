# frozen_string_literal: true

require "test_helper"

module MCP
  class ConnectorUpdaterTest < ActiveSupport::TestCase
    REGISTRY = "https://registry.modelcontextprotocol.io/v0.1/servers"

    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    # A minimal registry payload, so a "new version" can differ in exactly the
    # way each test is about.
    def entry(version:, inputs: [ { "name" => "API_TOKEN", "isRequired" => true, "isSecret" => true } ], identifier: "@acme/mcp")
      {
        "server" => {
          "name" => "io.github.acme/mcp", "title" => "Acme", "version" => version,
          "packages" => [ { "registryType" => "npm", "identifier" => identifier, "version" => version,
                            "runtimeHint" => "npx", "transport" => { "type" => "stdio" },
                            "environmentVariables" => inputs } ]
        },
        "_meta" => { "io.modelcontextprotocol.registry/official" => { "status" => "active", "isLatest" => true } }
      }
    end

    def install(version: "1.0.0", values: { "API_TOKEN" => "tok_original" })
      manifest = ConnectorManifest.normalize(entry(version: version))
      target = manifest["targets"].first
      attrs = ConnectorAttributes.build(manifest: manifest, target: target, values: values)
      @project.mcp_servers.create!(attrs)
    end

    def connector(version:)
      create(:connector, name: "io.github.acme/mcp", version: version,
                         manifest: ConnectorManifest.normalize(entry(version: version)))
    end

    def stub_fetch(version:, **entry_args)
      stub_request(:get, "#{REGISTRY}/io.github.acme%2Fmcp/versions/#{version}")
        .to_return(status: 200, body: entry(version: version, **entry_args).to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    # --------------------------------------------------------------- available?

    test "an update is offered when the catalog moved ahead" do
      assert ConnectorUpdater.available?(install(version: "1.0.0"), connector(version: "2.0.0"))
    end

    test "no update is offered when versions match" do
      assert_not ConnectorUpdater.available?(install(version: "1.0.0"), connector(version: "1.0.0"))
    end

    test "no update is offered when either version is unknown" do
      server = install
      server.update!(connector_version: nil)

      assert_not ConnectorUpdater.available?(server, connector(version: "2.0.0")),
                 "offering an update on a guess is worse than staying quiet"
    end

    # ------------------------------------------------------------------ preview

    test "preview names both versions without changing anything" do
      server = install(version: "1.0.0")
      stub_fetch(version: "2.0.0")

      preview = ConnectorUpdater.preview(server: server, connector: connector(version: "2.0.0"))

      assert_equal "1.0.0", preview.from_version
      assert_equal "2.0.0", preview.to_version
      assert_equal "1.0.0", server.reload.connector_version
    end

    test "preview surfaces inputs the new version newly requires" do
      server = install(version: "1.0.0")
      new_inputs = [ { "name" => "API_TOKEN", "isRequired" => true },
                     { "name" => "WORKSPACE_ID", "isRequired" => true } ]
      stub_fetch(version: "2.0.0", inputs: new_inputs)

      preview = ConnectorUpdater.preview(server: server, connector: connector(version: "2.0.0"))

      assert_equal [ "WORKSPACE_ID" ], preview.required_inputs.map { |i| i["key"] }
    end

    test "preview reports a target that no longer exists rather than switching silently" do
      server = install(version: "1.0.0")
      stub_fetch(version: "2.0.0", identifier: "@acme/renamed")

      preview = ConnectorUpdater.preview(server: server, connector: connector(version: "2.0.0"))

      assert_predicate preview, :blocked?
    end

    # -------------------------------------------------------------------- apply

    test "apply moves the install to the new version" do
      server = install(version: "1.0.0")
      stub_fetch(version: "2.0.0")

      ConnectorUpdater.apply(server: server, connector: connector(version: "2.0.0"))

      assert_equal "2.0.0", server.reload.connector_version
      assert_equal [ "@acme/mcp@2.0.0" ], server.args
    end

    test "apply keeps values the user already supplied" do
      server = install(version: "1.0.0", values: { "API_TOKEN" => "tok_original" })
      stub_fetch(version: "2.0.0")

      ConnectorUpdater.apply(server: server, connector: connector(version: "2.0.0"))

      assert_equal({ "API_TOKEN" => "tok_original" }, server.reload.env)
    end

    test "apply accepts answers for newly declared inputs" do
      server = install(version: "1.0.0")
      stub_fetch(version: "2.0.0", inputs: [ { "name" => "API_TOKEN", "isRequired" => true },
                                             { "name" => "WORKSPACE_ID", "isRequired" => true } ])

      ConnectorUpdater.apply(server: server, connector: connector(version: "2.0.0"),
                             values: { "WORKSPACE_ID" => "ws_9" })

      assert_equal({ "API_TOKEN" => "tok_original", "WORKSPACE_ID" => "ws_9" }, server.reload.env)
    end

    test "apply keeps a name the user changed" do
      server = install(version: "1.0.0")
      server.update!(name: "Acme (staging)")
      stub_fetch(version: "2.0.0")

      ConnectorUpdater.apply(server: server, connector: connector(version: "2.0.0"))

      assert_equal "Acme (staging)", server.reload.name, "an update is not the place to undo a rename"
    end

    test "apply refuses when the new version dropped the install option in use" do
      server = install(version: "1.0.0")
      stub_fetch(version: "2.0.0", identifier: "@acme/renamed")

      error = assert_raises(ConnectorUpdater::Error) do
        ConnectorUpdater.apply(server: server, connector: connector(version: "2.0.0"))
      end

      assert_match(/no longer offers/, error.message)
      assert_equal "1.0.0", server.reload.connector_version
    end

    test "apply re-baselines, so changes shipped with the new version are not reported as drift" do
      server = install(version: "1.0.0")
      server.update!(tool_drift: { "changed" => [ "search" ] }, tool_snapshot_at: Time.current)
      stub_fetch(version: "2.0.0")

      ConnectorUpdater.apply(server: server, connector: connector(version: "2.0.0"))

      assert_not server.reload.tool_drift?
    end
  end
end
