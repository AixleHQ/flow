# frozen_string_literal: true

require "test_helper"

module MCP
  # Contract tests for the registry boundary, driven by REAL payloads captured
  # from registry.modelcontextprotocol.io (test/fixtures/files/mcp_registry/).
  #
  # These fixtures are the point of the suite. The registry is in preview and
  # serves mixed schema versions today; when it changes shape, the failure
  # should surface here as a red test rather than in production as a broken
  # catalog. Refresh the fixtures deliberately, never by loosening assertions.
  class ConnectorManifestTest < ActiveSupport::TestCase
    def manifest_for(fixture)
      ConnectorManifest.normalize(JSON.parse(file_fixture("mcp_registry/#{fixture}.json").read))
    end

    def target_of(manifest, kind:, index: 0)
      manifest["targets"].select { |t| t["kind"] == kind }[index]
    end

    # ---------------------------------------------------------------- envelope

    test "reads registry status metadata from the _meta sibling of server" do
      manifest = manifest_for("remote_dual_transport")

      assert_equal "app.linear/linear", manifest["name"]
      assert_equal "active", manifest["status"]
      assert manifest["is_latest"]
      assert_equal "2025-09-18T15:51:15.598862Z", manifest["updated_at"]
    end

    test "normalizes both schema versions the registry serves today" do
      assert_equal "2025-09-29", manifest_for("remote_dual_transport")["schema_version"]
      assert_equal "2025-12-11", manifest_for("remote_secret_header")["schema_version"]
    end

    test "title is nil when absent so callers can fall back to name" do
      assert_nil manifest_for("remote_dual_transport")["title"]
      assert_equal "Linear-Task-Broker", manifest_for("remote_secret_header")["title"]
    end

    test "empty repository object does not become a blank url" do
      assert_nil manifest_for("remote_dual_transport")["repository_url"]
      assert_equal "https://github.com/adelaidasofia/linear-mcp", manifest_for("packages_pypi_and_mcpb")["repository_url"]
    end

    test "single-version endpoint uses the same envelope as list entries" do
      assert_equal manifest_for("remote_dual_transport"), manifest_for("single_version_response")
    end

    # ----------------------------------------------------------------- remotes

    test "ranks the non-deprecated remote transport ahead of sse" do
      targets = manifest_for("remote_dual_transport")["targets"]

      assert_equal %w[http sse], targets.map { |t| t["transport"] }
      assert_equal "https://mcp.linear.app/mcp", targets.first["url"]
    end

    # SSE is deprecated upstream and, decisively, unverifiable from here: a
    # direct POST answers 404, so an SSE install would never get a baseline,
    # never have its auth requirement detected, and never be checked for drift —
    # while looking exactly like one that had been.
    test "never offers an sse target, even as a connector's only remote" do
      dual = manifest_for("remote_dual_transport")["targets"].find { |t| t["transport"] == "sse" }
      only = manifest_for("remote_secret_header")["targets"].sole

      assert_not dual["supported"]
      assert_not only["supported"], "being the only way in does not make an unverifiable one acceptable"
      assert_match(/deprecated and cannot be verified/, only["unsupported_reason"])
      assert_match(/by hand/, only["unsupported_reason"], "the manual path is the escape hatch, so name it")
    end

    # isRequired defaults to false when the registry omits it.
    test "an omitted isRequired defaults to false" do
      input = ConnectorManifest.normalize(
        "server" => { "name" => "com.example/x", "version" => "1.0.0",
                      "remotes" => [ { "type" => "streamable-http", "url" => "https://example.com/mcp",
                                       "headers" => [ { "name" => "X-Key", "isSecret" => true } ] } ] }
      )["targets"].sole["inputs"].sole

      assert_not input["required"]
      assert input["secret"]
    end

    test "normalizes a secret header input" do
      input = manifest_for("remote_http_secret_header")["targets"].sole["inputs"].sole

      assert_equal "Authorization", input["key"]
      assert_equal "header", input["kind"]
      assert input["secret"]
      assert input["required"]
      assert_equal "string", input["format"]
    end

    # ---------------------------------------------------------------- packages

    # Runtimes are resolved against what the AGENT IMAGE ships (see
    # docker/base/Dockerfile). uvx is the one the MCP ecosystem publishes
    # against for Python servers, so the image carries it.
    test "launches python packages with uvx" do
      target = target_of(manifest_for("packages_pypi_and_mcpb"), kind: "package")

      assert_equal "pypi", target["registry_type"]
      assert_equal "uvx", target["runtime"]
      assert_empty target["runtime_prefix_args"]
      assert target["supported"]
    end

    test "honours an explicit pipx hint, which takes a subcommand" do
      target = ConnectorManifest.normalize(
        "server" => { "name" => "com.example/py", "version" => "1.0.0",
                      "packages" => [ { "registryType" => "pypi", "identifier" => "thing", "version" => "1.0.0",
                                        "runtimeHint" => "pipx", "transport" => { "type" => "stdio" } } ] }
      )["targets"].sole

      assert_equal "pipx", target["runtime"]
      assert_equal [ "run" ], target["runtime_prefix_args"]
    end

    # The catalog promises a runtime will be there. That promise is only as good
    # as the image, and the two live in different files — so pin them together.
    # A runtime added here without being added to the Dockerfile produces an
    # install that looks clean and fails at session start.
    test "every runtime the catalog offers is actually installed in the agent image" do
      dockerfile = Rails.root.join("docker/base/Dockerfile").read
      installed = {
        "npx" => dockerfile.include?("FROM node:"),
        "uvx" => dockerfile.include?("COPY --from=uv /uv /uvx"),
        "pipx" => dockerfile.match?(/^\s*pipx \\/)
      }

      ConnectorManifest::RUNTIMES.each_value do |resolved|
        runtime = resolved["runtime"]

        assert installed[runtime], "#{runtime} is offered by the catalog but not installed in docker/base/Dockerfile"
      end
    end

    test "no runtime is both offered and declared unavailable" do
      offered = ConnectorManifest::RUNTIMES.values.map { |r| r["runtime"] }

      assert_empty offered & ConnectorManifest::UNAVAILABLE_RUNTIMES.keys
    end

    # Agent containers have no Docker socket and no docker CLI, so an OCI package
    # would install cleanly and then never start.
    test "refuses an OCI package, naming Docker as the thing that is missing" do
      target = ConnectorManifest.normalize(
        "server" => { "name" => "com.example/img", "version" => "1.0.0",
                      "packages" => [ { "registryType" => "oci", "identifier" => "ghcr.io/example/mcp",
                                        "version" => "1.0.0", "transport" => { "type" => "stdio" } } ] }
      )["targets"].sole

      assert_not target["supported"]
      assert_match(/Docker, which agent containers do not have/, target["unsupported_reason"])
    end

    test "refuses a NuGet package for the same reason" do
      target = ConnectorManifest.normalize(
        "server" => { "name" => "com.example/net", "version" => "1.0.0",
                      "packages" => [ { "registryType" => "nuget", "identifier" => "Example.Mcp",
                                        "version" => "1.0.0", "transport" => { "type" => "stdio" } } ] }
      )["targets"].sole

      assert_not target["supported"]
      assert_match(/\.NET runtime/, target["unsupported_reason"])
    end

    test "marks a package with no known runtime unsupported instead of dropping it" do
      mcpb = manifest_for("packages_pypi_and_mcpb")["targets"].find { |t| t["registry_type"] == "mcpb" }

      assert_not_nil mcpb, "an unlaunchable target must still be visible so the UI can explain it"
      assert_not mcpb["supported"]
      assert_nil mcpb["runtime"]
      assert_match(/no known runtime for mcpb/, mcpb["unsupported_reason"])
      assert_equal "bd6c92b5ecb35a585679d43f2b2259e4ee03fa6d6f6e3eb6b54eed17289db372", mcpb["file_sha256"]
    end

    test "marks non-stdio package transports unsupported with a reason" do
      targets = manifest_for("package_http_transport_latest_version")["targets"]
      http = targets.find { |t| t["transport"] == "http" }

      assert_not http["supported"],
                 "launching a process and connecting to it over loopback is not expressible in agent MCP config"
      assert_match(/cannot express/, http["unsupported_reason"])
      assert_equal "http://127.0.0.1:{port}/mcp", http["url"], "kept for display so the UI can explain the refusal"
    end

    test "normalizes a required secret environment variable" do
      input = target_of(manifest_for("packages_pypi_and_mcpb"), kind: "package")["inputs"].sole

      assert_equal "LINEAR_PAT", input["key"]
      assert_equal "env", input["kind"]
      assert input["required"]
      assert input["secret"]
    end

    test "flags an unpinnable package version rather than trusting it" do
      target = target_of(manifest_for("package_http_transport_latest_version"), kind: "package")

      assert_equal "latest", target["version"]
      assert_not target["version_pinned"], "'latest' occurs in real payloads and must never be treated as pinned"
    end

    test "pinned versions are recognised" do
      assert target_of(manifest_for("package_npm_runtime_args"), kind: "package")["version_pinned"]
    end

    test "reads the package transport instead of assuming stdio" do
      transports = manifest_for("package_http_transport_latest_version")["targets"].map { |t| t["transport"] }

      assert_equal %w[stdio http sse], transports,
                   "all three are surfaced, ranked so the installable one leads"
    end

    test "literal runtime arguments are machinery, not questions for the user" do
      target = target_of(manifest_for("package_npm_runtime_args"), kind: "package")

      assert_equal [ "-y" ], target["runtime_arguments"].map { |a| a["value_template"] }
      assert_equal %w[env], target["inputs"].map { |i| i["kind"] }.uniq,
                   "only environment variables are prompted here; the -y literal is not"
    end

    test "normalizes a named argument with a default" do
      port = manifest_for("package_http_transport_latest_version")["targets"]
             .find { |t| t["transport"] == "sse" }["inputs"]
             .find { |i| i["key"] == "port" }

      assert_equal "named", port["arg_type"]
      assert_equal "number", port["format"]
      assert_equal "8089", port["default"]
      assert port["required"]
    end

    test "normalizes a repeated positional argument, keyed by its value hint" do
      input = target_of(manifest_for("package_positional_repeated_arg"), kind: "package")["inputs"].sole

      assert_equal "directory", input["key"]
      assert_equal "positional", input["arg_type"]
      assert_equal "filepath", input["format"]
      assert input["repeated"]
    end

    test "ranks remote targets ahead of package targets" do
      manifest = ConnectorManifest.normalize(
        "server" => {
          "name" => "com.example/mixed",
          "version" => "1.0.0",
          "packages" => [ { "registryType" => "npm", "identifier" => "x", "version" => "1.0.0", "transport" => { "type" => "stdio" } } ],
          "remotes" => [ { "type" => "streamable-http", "url" => "https://example.com/mcp" } ]
        }
      )

      assert_equal %w[remote package], manifest["targets"].map { |t| t["kind"] }
    end

    test "ignores unknown keys and missing metadata rather than failing discovery" do
      manifest = ConnectorManifest.normalize(
        "server" => { "name" => "com.example/minimal", "version" => "1.0.0", "somethingNew" => { "a" => 1 } }
      )

      assert_equal "com.example/minimal", manifest["name"]
      assert_equal "active", manifest["status"]
      assert manifest["is_latest"]
      assert_empty manifest["targets"]
    end
  end
end
