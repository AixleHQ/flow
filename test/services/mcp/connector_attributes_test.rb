# frozen_string_literal: true

require "test_helper"

module MCP
  # The central claim of the connector-catalog research: a registry manifest
  # projects onto an ordinary MCPServer row with no new concepts. These tests
  # drive REAL registry payloads all the way to persisted attributes, so the
  # claim is falsifiable rather than asserted.
  #
  # Real collaborators throughout (testing doctrine R1/R5): the manifest is
  # produced by the real normalizer and the result is saved through the real
  # model, because "the attributes are right" is only interesting if the row
  # actually validates.
  class ConnectorAttributesTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
    end

    def manifest_for(fixture)
      ConnectorManifest.normalize(JSON.parse(file_fixture("mcp_registry/#{fixture}.json").read))
    end

    def build_attributes(fixture, values: {}, kind: nil, index: 0)
      manifest = manifest_for(fixture)
      targets = kind ? manifest["targets"].select { |t| t["kind"] == kind } : manifest["targets"]
      ConnectorAttributes.build(manifest: manifest, target: targets[index], values: values)
    end

    # ------------------------------------------------------------------ remote

    test "installs a remote connector as a valid project MCP server" do
      attrs = build_attributes("remote_dual_transport")
      server = @project.mcp_servers.create!(attrs)

      assert_predicate server, :persisted?
      assert_equal "app.linear/linear", server.name, "no title in the payload, so the name is used"
      assert_equal "http", server.transport
      assert_equal "https://mcp.linear.app/mcp", server.url
      assert_predicate server, :custom?
    end

    test "records provenance so the install can be traced and later diffed" do
      server = @project.mcp_servers.create!(build_attributes("remote_http_secret_header", values: { "Authorization" => "sig" }))

      assert_predicate server, :from_connector?
      assert_equal "ai.adadvisor/mcp-server", server.connector_name
      assert_equal "1.0.1", server.connector_version
      assert_equal "ai.adadvisor/mcp-server", server.connector_manifest["name"]
    end

    test "records which target was installed, not just the whole manifest" do
      server = @project.mcp_servers.create!(
        build_attributes("packages_pypi_and_mcpb", values: { "LINEAR_PAT" => "lin_api_x" })
      )

      assert_equal "pypi", server.installed_connector_target["registry_type"],
                   "a connector offers several targets; drift detection needs the one actually used"
    end

    test "installs an unpinnable package but keeps the missing pin visible" do
      server = @project.mcp_servers.create!(
        build_attributes("package_http_transport_latest_version", values: { "allowed-directories" => "/w" })
      )

      assert_predicate server, :persisted?, "the catalog does not gatekeep unpinnable packages"
      assert_not server.connector_version_pinned?
      assert_not_includes server.args.join(" "), "@latest"
    end

    test "a pinned package install reports itself as pinned" do
      server = @project.mcp_servers.create!(build_attributes("package_npm_runtime_args", values: { "GCS_BUCKET" => "b" }))

      assert_predicate server, :connector_version_pinned?
    end

    test "pinning does not apply to remote connectors or hand-authored servers" do
      remote = @project.mcp_servers.create!(build_attributes("remote_dual_transport"))
      manual = @project.mcp_servers.create!(name: "Manual", url: "https://mcp.example.com", transport: :http)

      assert_predicate remote, :connector_version_pinned?
      assert_predicate manual, :connector_version_pinned?
      assert_not manual.from_connector?
      assert_nil manual.installed_connector_target
    end

    test "uses the human title as the server label when the registry provides one" do
      assert_equal "AdAdvisor MCP Server", build_attributes("remote_http_secret_header")[:name]
    end

    test "writes a declared header from the value the user supplied" do
      attrs = build_attributes("remote_http_secret_header", values: { "Authorization" => "abc123" })

      assert_equal({ "Authorization" => "abc123" }, attrs[:headers])
    end

    test "omits a header the user left blank instead of writing an empty string" do
      assert_empty build_attributes("remote_http_secret_header")[:headers]
    end

    test "the stored snapshot carries input declarations but never their values" do
      attrs = build_attributes("remote_http_secret_header", values: { "Authorization" => "s3cret" })
      snapshot = attrs[:connector_manifest].to_json

      assert_includes snapshot, "Authorization", "the declaration must survive for later drift diffing"
      assert_not_includes snapshot, "s3cret", "a secret value must never reach the snapshot"
    end

    # ----------------------------------------------------------------- package

    test "installs an npm package connector with the executable and argv split as the adapters emit them" do
      attrs = build_attributes("package_npm_runtime_args", values: { "GCS_BUCKET" => "my-bucket" })

      assert_equal "stdio", attrs[:transport]
      assert_equal "npx", attrs[:command]
      assert_equal [ "-y", "remote-filesystem-mcp-server@0.1.2" ], attrs[:args]
      assert_equal({ "GCS_BUCKET" => "my-bucket" }, attrs[:env])
    end

    test "pins the exact version in the emitted package spec" do
      assert_includes build_attributes("package_npm_runtime_args")[:args], "remote-filesystem-mcp-server@0.1.2"
    end

    test "never fabricates a pin for a package the registry did not pin" do
      attrs = build_attributes("package_http_transport_latest_version", values: { "allowed-directories" => "/workspace" })

      assert_includes attrs[:args], "@agent-infra/mcp-server-filesystem"
      assert_not_includes attrs[:args].join(" "), "@latest"
    end

    test "renders a named argument as a flag and value" do
      attrs = build_attributes("package_http_transport_latest_version", values: { "allowed-directories" => "/workspace" })

      assert_equal [ "@agent-infra/mcp-server-filesystem", "--allowed-directories", "/workspace" ], attrs[:args]
    end

    test "writes nothing for an input the caller left blank, even when a default is declared" do
      manifest = manifest_for("package_http_transport_latest_version")
      sse = manifest["targets"].find { |t| t["transport"] == "sse" }

      assert_equal({ "port" => "8089" }, ConnectorManifest.default_values(sse))

      args = build_attributes("package_http_transport_latest_version", values: { "allowed-directories" => "/w" })[:args]

      assert_not_includes args, "8089", "a declared default is a form suggestion, never applied on the user's behalf"
    end

    test "refuses a package target that would have to be launched and connected to separately" do
      manifest = manifest_for("package_http_transport_latest_version")
      http = manifest["targets"].find { |t| t["transport"] == "http" }

      error = assert_raises(ConnectorAttributes::UnsupportedTargetError) do
        ConnectorAttributes.build(manifest: manifest, target: http)
      end
      assert_match(/cannot express/, error.message)
    end

    test "repeats a repeated positional argument once per supplied value" do
      attrs = build_attributes("package_positional_repeated_arg", values: { "directory" => [ "/a", "/b" ] })

      assert_equal [ "@j0hanz/filesystem-mcp@1.0.0", "/a", "/b" ], attrs[:args]
    end

    test "a package connector persists as a valid stdio server" do
      server = @project.mcp_servers.create!(
        build_attributes("packages_pypi_and_mcpb", values: { "LINEAR_PAT" => "lin_api_x" })
      )

      assert_predicate server, :persisted?
      assert_predicate server, :transport_stdio?
      assert_equal "uvx", server.command
      assert_equal [ "adelaidasofia-linear-mcp@0.3.2" ], server.args
      assert_equal({ "LINEAR_PAT" => "lin_api_x" }, server.env)
    end

    # The command shown in the install dialog must be the command that actually
    # runs — a security warning naming the wrong binary is worse than none.
    test "the displayed launch command matches what will be executed" do
      manifest = manifest_for("packages_pypi_and_mcpb")
      target = manifest["targets"].find { |t| t["supported"] }
      serialized = ConnectorResource.new(Connector.new(name: manifest["name"], manifest: manifest))
                                    .to_h.deep_symbolize_keys
      displayed = serialized[:targets].find { |t| t[:supported] }[:command]
      attrs = ConnectorAttributes.build(manifest: manifest, target: target, values: {})

      assert_equal "uvx adelaidasofia-linear-mcp@0.3.2", displayed
      assert_equal displayed, "#{attrs[:command]} #{attrs[:args].join(' ')}"
    end

    test "refuses to build attributes for a target with no runtime" do
      manifest = manifest_for("packages_pypi_and_mcpb")
      mcpb = manifest["targets"].find { |t| t["registry_type"] == "mcpb" }

      assert_raises(ConnectorAttributes::UnsupportedTargetError) do
        ConnectorAttributes.build(manifest: manifest, target: mcpb)
      end
    end

    # ------------------------------------------------------------ coexistence

    test "leaves provenance null for a hand-authored server" do
      server = @project.mcp_servers.create!(name: "Internal", url: "https://mcp.internal.example.com", transport: :http)

      assert_nil server.connector_name
      assert_empty server.connector_manifest
    end

    test "a catalog install stays editable by hand afterwards" do
      server = @project.mcp_servers.create!(build_attributes("remote_dual_transport"))

      server.update!(url: "https://linear.self-hosted.example.com/mcp")

      assert_equal "https://linear.self-hosted.example.com/mcp", server.reload.url
      assert_equal "app.linear/linear", server.connector_name, "provenance is a label, not a lock"
    end
  end
end
