# frozen_string_literal: true

module MCP
  # Normalizes an Official MCP Registry entry (`server.json` + registry `_meta`)
  # into the connector manifest shape this app stores and renders forms from.
  #
  # This is the anti-corruption layer at the registry boundary. The registry is
  # in preview ("breaking changes or data resets may occur"), already serves
  # MIXED schema versions in a single list response (2025-09-29 and 2025-12-11
  # both appear in production payloads today), and has moved its API path once
  # already. Nothing upstream of this class may see a raw registry hash: the
  # installer, the form renderer and the stored snapshot all consume the
  # normalized shape, so a schema change is a change to this file plus its
  # fixtures rather than a change spread across the feature.
  #
  # Output is plain string-keyed Hashes, not value objects, because the result
  # is persisted verbatim as jsonb (the install snapshot) and round-tripping
  # through Postgres must not change its shape.
  #
  # ============================ WIRE-FORMAT NOTES ============================
  # Facts below were established against live registry payloads (see
  # test/fixtures/files/mcp_registry/*.json), and several contradict a plain
  # reading of the published JSON Schema. Do not "simplify" them away:
  #
  #   1. `_meta` is a SIBLING of `server`, not a key inside it. A registry
  #      entry is {"server": {...}, "_meta": {...}}. Both the list endpoint and
  #      the single-version endpoint use this envelope.
  #   2. `packages[].transport.type` is NOT always "stdio". Real packages ship
  #      "streamable-http"/"sse" with a LOCAL url template (e.g.
  #      "http://127.0.0.1:{port}/mcp") — you launch the process and then speak
  #      HTTP to it. Read the transport; never infer it from the presence of a
  #      package.
  #   3. `version: "latest"` occurs in the wild despite the schema stating that
  #      exact versions are required. It is surfaced as version_pinned: false
  #      rather than silently accepted — exact-version pinning is the primary
  #      supply-chain control for catalog installs, so an unpinnable package
  #      must be visible to the caller, not papered over.
  #   4. `title` is frequently absent; callers fall back to `name`.
  #
  # Unknown keys are ignored rather than rejected: a registry that adds fields
  # must not break discovery for servers we can already model.
  class ConnectorManifest
    # Remote transport type (registry vocabulary) => our MCPServer#transport enum.
    # "streamable-http" is the current standard; "sse" is formally deprecated
    # upstream (SEP-2596, ~12 month offramp) and only mapped for compatibility.
    TRANSPORT_MAP = {
      "streamable-http" => "http",
      "http" => "http",
      "sse" => "sse",
      "stdio" => "stdio"
    }.freeze

    # Preference order when a server offers several ways in. Remote beats local
    # (nothing to execute), and within remotes the non-deprecated transport wins.
    TRANSPORT_RANK = { "http" => 0, "sse" => 1, "stdio" => 2 }.freeze

    # What the AGENT CONTAINER can actually launch. Verified against
    # docker/base/Dockerfile, not against what the registry suggests: a manifest
    # names the runtime its publisher used, which says nothing about ours.
    #
    #   npx  — node:22-slim base image
    #   uvx  — copied from Astral's image; the runtime the MCP ecosystem
    #          overwhelmingly publishes against for Python servers
    #   pipx — also present, and used when a publisher explicitly asks for it
    #
    # Adding one here without adding it to docker/base/Dockerfile produces an
    # install that looks clean and then fails at session start.
    RUNTIMES = {
      "npx" => { "runtime" => "npx", "prefix_args" => [] },
      "uvx" => { "runtime" => "uvx", "prefix_args" => [] },
      "pipx" => { "runtime" => "pipx", "prefix_args" => [ "run" ] }
    }.freeze

    # Runtimes a manifest may ask for that this platform cannot provide, with the
    # reason a user sees. `docker` is the notable one: agent containers have no
    # Docker socket and no docker CLI, so an OCI package cannot be launched —
    # offering it would install a connector that silently never starts.
    UNAVAILABLE_RUNTIMES = {
      "docker" => "OCI packages need Docker, which agent containers do not have",
      "dnx" => "NuGet packages need the .NET runtime, which agent containers do not have"
    }.freeze

    # Default runtime per package registry when the entry omits `runtimeHint`.
    # `mcpb` is deliberately absent: it is a downloadable bundle, not something a
    # package runner executes.
    RUNTIME_BY_REGISTRY_TYPE = {
      "npm" => "npx",
      "pypi" => "uvx",
      "oci" => "docker",
      "nuget" => "dnx"
    }.freeze

    OFFICIAL_META_KEY = "io.modelcontextprotocol.registry/official"

    # BUMP THIS whenever normalization changes what it produces — a new field, a
    # different `supported` decision, a changed target id. The output is stored,
    # so without a bump the mirror keeps serving manifests built under the old
    # rules and the change appears to do nothing. ConnectorCatalogSync forces a
    # full re-walk when any mirrored row was built by an older version.
    #
    # 2 — SSE targets are no longer installable (deprecated upstream and
    #     unverifiable from here).
    # 3 — runtimes are resolved against what the agent image actually ships:
    #     pypi launches via uvx (added to the image), pipx is honoured when a
    #     publisher names it, and OCI/NuGet packages are refused outright rather
    #     than emitting a command that cannot run.
    VERSION = 3

    # Version strings that do not identify an immutable artifact.
    UNPINNED_VERSIONS = [ "latest", "", nil ].freeze

    SSE_UNSUPPORTED_REASON = "the SSE transport is deprecated and cannot be verified from here — " \
                             "add this server by hand if you need it"

    class << self
      # Looks a target up by its stable id.
      #
      # Install submits an id rather than a position because the browser's copy
      # comes from the mirror while the install itself re-fetches the manifest
      # live — and target ORDER is not guaranteed to match between the two. An
      # index would silently install the wrong target when it drifted.
      #
      # @return [Hash, nil]
      def find_target(manifest, id)
        Array(manifest["targets"]).find { |t| t["id"] == id }
      end

      # Declared defaults for a target's inputs, for PRE-FILLING an install form
      # (or a non-interactive caller's values hash).
      #
      # Defaults deliberately live here rather than inside ConnectorAttributes:
      # a default is a suggestion to show the user, not a value to write behind
      # their back. Persisting one silently would record a choice nobody made,
      # and would override the package's own default if it ever changed. Callers
      # that want defaults ask for them; the mapper writes only what it is given.
      #
      # @param target [Hash] one entry from a normalized manifest's "targets"
      # @return [Hash] input key => default value
      def default_values(target)
        Array(target["inputs"]).each_with_object({}) do |input, acc|
          acc[input["key"]] = input["default"] if input["default"].present?
        end
      end

      # @param entry [Hash] one registry entry: {"server" => {...}, "_meta" => {...}}
      # @return [Hash] normalized, jsonb-ready manifest
      def normalize(entry)
        entry = entry.to_h.deep_stringify_keys
        server = entry["server"] || {}
        official = entry.dig("_meta", OFFICIAL_META_KEY) || {}

        {
          "normalizer_version" => VERSION,
          "name" => server["name"],
          "title" => server["title"].presence,
          "description" => server["description"],
          "version" => server["version"],
          "schema_version" => schema_version(server["$schema"]),
          "repository_url" => server.dig("repository", "url").presence,
          "status" => official["status"] || "active",
          "is_latest" => official.fetch("isLatest", true),
          "published_at" => official["publishedAt"],
          "updated_at" => official["updatedAt"],
          "targets" => targets_for(server)
        }
      end

      private

      # Stable across re-fetches of the same server version, so a form rendered
      # from the mirror can name the target an install resolves live.
      def target_id(kind, transport, discriminator)
        [ kind, transport, discriminator.presence ].compact.join(":")
      end

      # "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json"
      # => "2025-12-11". Retained for diagnostics: when a payload stops
      # normalizing correctly, the schema version is the first thing to check.
      def schema_version(url)
        url.to_s[%r{/schemas/([^/]+)/}, 1]
      end

      def targets_for(server)
        targets = Array(server["remotes"]).map { |r| remote_target(r) } +
                  Array(server["packages"]).map { |p| package_target(p) }
        targets = targets.compact

        # Installable targets first — an unsupported one must never be the
        # default offered to the user — then remote over local, then the
        # non-deprecated transport.
        targets.sort_by do |t|
          [ t["supported"] ? 0 : 1, t["kind"] == "remote" ? 0 : 1, TRANSPORT_RANK.fetch(t["transport"], 9) ]
        end
      end

      # SSE is not installable from the catalog. The protocol deprecated it
      # (SEP-2596, on a twelve-month offramp), and — decisively — this platform
      # cannot VERIFY it: the deprecated transport opens with a GET stream that
      # advertises a separate message endpoint, so the direct POST every probe
      # makes answers 404. An SSE install would therefore never get a tool
      # baseline, never have its auth requirement detected, and never be checked
      # for drift, while looking exactly like one that had been.
      #
      # 413 of 19,541 mirrored connectors offer only SSE. Those remain addable by
      # hand — the manual form still supports the transport — which is the whole
      # reason that path stays first-class.
      def remote_target(remote)
        transport = TRANSPORT_MAP[remote["type"].to_s]
        return nil if transport.blank?

        deprecated_sse = transport == "sse"

        {
          "id" => target_id("remote", transport, remote["url"]),
          "kind" => "remote",
          "transport" => transport,
          "url" => remote["url"],
          "supported" => !deprecated_sse,
          "unsupported_reason" => deprecated_sse ? SSE_UNSUPPORTED_REASON : nil,
          "inputs" => Array(remote["headers"]).map { |h| key_value_input(h, "header") }
        }
      end

      def package_target(package)
        transport = TRANSPORT_MAP[package.dig("transport", "type").to_s]
        return nil if transport.blank?

        registry_type = package["registryType"].to_s
        hint = package["runtimeHint"].presence || RUNTIME_BY_REGISTRY_TYPE[registry_type]
        resolved = RUNTIMES[hint]
        runtime = resolved&.dig("runtime")
        version = package["version"].to_s
        pinned = UNPINNED_VERSIONS.exclude?(package["version"]) && !version.match?(/[\^~*><]|\s-\s/)
        blocker = package_blocker(transport, registry_type, runtime, hint)

        {
          "id" => target_id("package", transport, "#{registry_type}:#{package['identifier']}"),
          "kind" => "package",
          "transport" => transport,
          # Present for packages whose transport is http/sse: the process is
          # launched locally and then spoken to over this (templated) url.
          "url" => package.dig("transport", "url"),
          "registry_type" => registry_type,
          "identifier" => package["identifier"],
          "version" => package["version"],
          "version_pinned" => pinned,
          "runtime" => runtime,
          "runtime_prefix_args" => resolved&.dig("prefix_args") || [],
          "file_sha256" => package["fileSha256"],
          # A target we cannot install is still surfaced (so the UI can explain
          # why) rather than dropped, which would look like the server having
          # no install path at all.
          "supported" => blocker.nil?,
          "unsupported_reason" => blocker,
          "runtime_arguments" => Array(package["runtimeArguments"]).map { |a| argument_input(a) },
          "package_arguments" => Array(package["packageArguments"]).map { |a| argument_input(a) },
          "inputs" => Array(package["environmentVariables"]).map { |e| key_value_input(e, "env") } +
                      Array(package["packageArguments"]).filter_map { |a| argument_prompt(a) }
        }
      end

      # Why a package target cannot be installed, or nil when it can.
      #
      # Non-stdio package transports are refused deliberately. Such a target
      # means "launch this process locally, then speak HTTP to it on loopback"
      # — and an agent's MCP config has no way to express that: the adapters
      # emit command/args/env for stdio entries and url/headers for everything
      # else, never both (see Agents::ClaudeCodeAdapter#mcp_config). Installing
      # one would write a config pointing at a port where nothing is listening.
      # The loopback url would also, correctly, be rejected by UrlSafetyValidator.
      def package_blocker(transport, registry_type, runtime, hint)
        return UNAVAILABLE_RUNTIMES[hint] if UNAVAILABLE_RUNTIMES.key?(hint)
        return "no known runtime for #{registry_type.presence || 'this'} packages" if runtime.blank?
        return nil if transport == "stdio"

        "#{transport} package transports require launching and connecting separately, " \
          "which agent MCP config cannot express"
      end

      # Header / environment-variable inputs. `name` is the wire key; a header
      # or env var with a literal `value` is not asked of the user.
      def key_value_input(input, kind)
        base_input(input).merge(
          "kind" => kind,
          "key" => input["name"],
          "value_template" => input["value"]
        )
      end

      def argument_input(argument)
        base_input(argument).merge(
          "kind" => "arg",
          "arg_type" => argument["type"] || "positional",
          "key" => argument["name"] || argument["valueHint"],
          "value_template" => argument["value"],
          "value_hint" => argument["valueHint"],
          "repeated" => argument.fetch("isRepeated", false)
        )
      end

      # Only arguments without a fixed `value` are asked of the user; a literal
      # like {"value" => "-y"} is machinery, not a question.
      def argument_prompt(argument)
        return nil if argument["value"].present?

        argument_input(argument)
      end

      def base_input(input)
        {
          "description" => input["description"],
          "format" => input["format"] || "string",
          "required" => input.fetch("isRequired", false),
          "secret" => input.fetch("isSecret", false),
          "default" => input["default"],
          "choices" => input["choices"],
          "placeholder" => input["placeholder"],
          "variables" => input["variables"]
        }.compact
      end
    end
  end
end
