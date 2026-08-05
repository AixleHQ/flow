# frozen_string_literal: true

require "test_helper"

module MCP
  # The installer is the only path that turns a catalog entry into an MCPServer,
  # and the row it writes is what every agent adapter later emits into .mcp.json.
  #
  # The argv assertions are the point of the package tests: `command` and `args`
  # together ARE the launch line, so a package install that persists one without
  # the other produces a server that cannot start.
  class ConnectorInstallerTest < ActiveSupport::TestCase
    REGISTRY = "https://registry.modelcontextprotocol.io/v0.1/servers"
    PACKAGE_NAME = "com.pulsemcp/remote-filesystem"

    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    def entry(fixture)
      JSON.parse(file_fixture("mcp_registry/#{fixture}.json").read)
    end

    def connector_for(fixture, **attrs)
      manifest = ConnectorManifest.normalize(entry(fixture))
      create(:connector, name: manifest["name"], version: manifest["version"], manifest: manifest, **attrs)
    end

    def stub_registry(name:, version:, fixture:)
      stub_request(:get, "#{REGISTRY}/#{CGI.escape(name)}/versions/#{version}")
        .to_return(status: 200, body: entry(fixture).to_json, headers: { "Content-Type" => "application/json" })
    end

    def install(connector, target_index: 0, values: {})
      target = connector.manifest["targets"][target_index]
      ConnectorInstaller.call(connector: connector, target_id: target["id"], values: values, project: @project)
    end

    # ------------------------------------------------------------- package/stdio

    test "installing a package connector persists the whole launch line" do
      connector = connector_for("package_npm_runtime_args")
      stub_registry(name: PACKAGE_NAME, version: "0.1.2", fixture: "package_npm_runtime_args")

      server = install(connector, values: { "GCS_BUCKET" => "my-bucket" }).server

      assert_equal "stdio", server.transport.to_s
      assert_equal "npx", server.command
      # The runtime's own argument leads, then the version-pinned package spec.
      assert_equal [ "-y", "remote-filesystem-mcp-server@0.1.2" ], server.args
      assert_equal({ "GCS_BUCKET" => "my-bucket" }, server.env)
    end

    test "a stdio install records its catalog provenance" do
      connector = connector_for("package_npm_runtime_args")
      stub_registry(name: PACKAGE_NAME, version: "0.1.2", fixture: "package_npm_runtime_args")

      server = install(connector, values: { "GCS_BUCKET" => "my-bucket" }).server

      assert_equal PACKAGE_NAME, server.connector_name
      assert_equal "0.1.2", server.connector_version
      assert server.connector_version_pinned?
      # stdio is never probed (executing the package here is the thing we refuse
      # to do), so it must not come back claiming a verified baseline.
      assert_not server.tool_baseline?
    end

    test "installing the same connector twice keeps both servers under distinct names" do
      connector = connector_for("package_npm_runtime_args")
      stub_registry(name: PACKAGE_NAME, version: "0.1.2", fixture: "package_npm_runtime_args")

      first = install(connector, values: { "GCS_BUCKET" => "one" }).server
      second = install(connector, values: { "GCS_BUCKET" => "two" }).server

      assert_not_equal first.name, second.name
      assert_equal "#{first.name} (2)", second.name
    end

    # ------------------------------------------------------------------- staleness

    test "an unreachable registry installs from the mirrored manifest and says so" do
      connector = connector_for("package_npm_runtime_args")
      stub_request(:get, %r{#{Regexp.escape(REGISTRY)}/.*}).to_timeout

      result = install(connector, values: { "GCS_BUCKET" => "my-bucket" })

      assert result.stale
      assert_equal [ "-y", "remote-filesystem-mcp-server@0.1.2" ], result.server.args
    end

    test "a target the connector no longer offers is refused" do
      connector = connector_for("package_npm_runtime_args")
      stub_registry(name: PACKAGE_NAME, version: "0.1.2", fixture: "package_npm_runtime_args")

      error = assert_raises(ConnectorInstaller::Error) do
        ConnectorInstaller.call(connector: connector, target_id: "gone", values: {}, project: @project)
      end

      assert_match(/no longer offered/, error.message)
    end
  end
end
