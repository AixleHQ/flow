# frozen_string_literal: true

module MCP
  # Projects a normalized connector manifest target (see MCP::ConnectorManifest)
  # plus the values a user supplied in the install form onto MCPServer attributes.
  #
  # This is the half of the catalog that must be exactly right: everything after
  # it is the ordinary MCPServer path that already works — SessionConfigResolver,
  # the three agent adapters, credential masking. A catalog install is not a new
  # kind of row, it is an ordinary row somebody else filled in.
  #
  # Deliberately NOT decided here:
  #   * auth_type — a remote with no declared header inputs is usually OAuth, but
  #     "usually" is not a basis for silently configuring authentication. The
  #     caller decides, and the OAuth discovery flow confirms.
  #   * credential_scope — has no counterpart in the registry manifest (it
  #     describes what a server needs, not who owns the credential). Stays a
  #     local choice, defaulting to the model default.
  #
  # Secrets note: `values` carries user-supplied secrets and flows into the
  # encrypted/masked headers+env columns. The manifest snapshot returned in
  # `connector_manifest` records input DECLARATIONS only — it must stay safe to
  # display, diff and log.
  class ConnectorAttributes
    class UnsupportedTargetError < StandardError; end

    class << self
      # @param manifest [Hash] normalized manifest (string keys)
      # @param target [Hash] one entry from manifest["targets"]
      # @param values [Hash] user-supplied input values, keyed by input "key"
      # @return [Hash] attributes for MCPServer.new / #update
      def build(manifest:, target:, values: {})
        raise UnsupportedTargetError, target["unsupported_reason"].to_s unless target["supported"]

        values = values.to_h.stringify_keys

        base = {
          name: manifest["title"].presence || manifest["name"],
          description: manifest["description"],
          kind: :custom,
          transport: target["transport"],
          connector_name: manifest["name"],
          connector_version: manifest["version"],
          # The snapshot records WHICH target was installed alongside the whole
          # manifest. A server commonly offers several ways in (remote + package,
          # or one package per transport), so without this, later drift detection
          # cannot tell which declarations to diff against, and the UI cannot say
          # whether this install is version-pinned.
          connector_manifest: manifest.merge("installed_target" => target)
        }

        base.merge(target["kind"] == "remote" ? remote_attributes(target, values) : package_attributes(target, values))
      end

      private

      def remote_attributes(target, values)
        {
          url: interpolate(target["url"], values),
          headers: wire_values(target["inputs"], "header", values)
        }
      end

      # Only stdio packages reach here: ConnectorManifest marks every other
      # package transport unsupported, because agent MCP config cannot both
      # launch a process and connect to it over http.
      def package_attributes(target, values)
        {
          command: target["runtime"],
          args: package_args(target, values),
          env: wire_values(target["inputs"], "env", values)
        }
      end

      # argv for the launched process, in the order a package runner expects:
      #   <runtime> <runtime args> <identifier[@version]> <package args>
      # `command` holds the executable alone and `args` the rest, which is the
      # shape the agent adapters emit verbatim into .mcp.json.
      # `prefix_args` are the runtime's own, not the publisher's: `pipx run` takes
      # a subcommand before the package spec. They lead, ahead of anything the
      # manifest asked for.
      def package_args(target, values)
        Array(target["runtime_prefix_args"]) +
          Array(target["runtime_arguments"]).flat_map { |a| render_argument(a, values) } +
          [ package_spec(target) ].compact +
          Array(target["package_arguments"]).flat_map { |a| render_argument(a, values) }
      end

      # Pinning the exact version in the EMITTED spec is the primary defence
      # against a rug pull: without it the package runner is free to resolve a
      # newer release at every session start. The same lesson is already encoded
      # for @playwright/mcp in Agents::BaseAdapter. When the registry itself
      # carries an unpinnable version ("latest" occurs in real payloads), the
      # identifier is emitted bare rather than pinned to a lie — callers are
      # expected to refuse or resolve such targets, using target["version_pinned"].
      def package_spec(target)
        identifier = target["identifier"]
        return nil if identifier.blank?
        return identifier unless target["version_pinned"]
        # OCI images pin with ':', package registries with '@'.
        return "#{identifier}:#{target['version']}" if target["registry_type"] == "oci"

        "#{identifier}@#{target['version']}"
      end

      def render_argument(argument, values)
        value = argument["value_template"].present? ? interpolate(argument["value_template"], values) : values[argument["key"]]
        return [] if value.blank?

        return Array(value).map(&:to_s) if argument["arg_type"] != "named"

        Array(value).flat_map { |v| [ "--#{argument['key']}", v.to_s ] }
      end

      # Headers/env destined for the wire. An input with a literal `value`
      # template is machinery (often a variable-substituted prefix like
      # "Bearer {token}") and is rendered rather than asked for.
      #
      # Nothing is invented for an input the caller left blank — see
      # ConnectorManifest.default_values for why defaults are pre-filled by the
      # caller rather than applied here.
      def wire_values(inputs, kind, values)
        Array(inputs).select { |i| i["kind"] == kind }.each_with_object({}) do |input, acc|
          raw = input["value_template"].present? ? interpolate(input["value_template"], values) : values[input["key"]]
          acc[input["key"]] = raw.to_s if raw.present?
        end
      end

      # `{name}` substitution, used by remote url templates, local loopback urls
      # ("http://127.0.0.1:{port}/mcp") and header value templates.
      def interpolate(template, values)
        return template if template.blank?

        template.gsub(/\{(\w+)\}/) { values[Regexp.last_match(1)].to_s.presence || Regexp.last_match(0) }
      end
    end
  end
end
