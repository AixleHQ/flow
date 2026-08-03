# frozen_string_literal: true

module MCP
  # Moves an installed connector to the version the catalog now carries.
  #
  # Never automatic. Updating changes which code runs — a new package version, a
  # new endpoint, possibly new tools — and doing that silently would undo the
  # point of pinning the version in the first place. The platform offers the
  # update and shows what changes; a person applies it.
  #
  # Two things make an update more than a version-string bump:
  #   * the new version may DECLARE NEW REQUIRED INPUTS the install has no value
  #     for, so the caller has to collect them before it can proceed;
  #   * the chosen install target may be gone entirely (a connector that dropped
  #     its npm package, say), which is a refusal rather than a silent switch to
  #     a different target the user never chose.
  class ConnectorUpdater
    class Error < StandardError; end

    Preview = Struct.new(:from_version, :to_version, :added_inputs, :removed_inputs, :target_missing,
                         keyword_init: true) do
      def target_missing? = !!target_missing
      def blocked? = target_missing?
      # Inputs the user must supply before this update can be applied: newly
      # required, and not already answered by a stored value.
      def required_inputs = added_inputs.select { |i| i["required"] }
    end

    class << self
      # Whether the catalog has a different version than the one installed.
      # A blank version on either side means "cannot tell", which is not an
      # update — offering one on a guess would be worse than staying quiet.
      def available?(server, connector)
        return false if server.connector_version.blank? || connector&.version.blank?

        server.connector_version != connector.version
      end

      # What would change, without changing anything.
      def preview(server:, connector:)
        manifest = latest_manifest(connector)
        target = manifest && ConnectorManifest.find_target(manifest, installed_target_id(server))

        Preview.new(
          from_version: server.connector_version,
          to_version: manifest&.dig("version") || connector.version,
          added_inputs: target ? input_diff(target, installed_target(server)) : [],
          removed_inputs: target ? input_diff(installed_target(server), target) : [],
          target_missing: target.nil?
        )
      end

      # Applies the update, preserving every value the user already supplied for
      # inputs the new version still declares.
      #
      # @param values [Hash] answers for newly declared inputs
      def apply(server:, connector:, values: {})
        manifest = latest_manifest(connector)
        raise Error, "Could not fetch the new version from the registry" if manifest.blank?

        target = ConnectorManifest.find_target(manifest, installed_target_id(server))
        raise Error, "This version no longer offers the install option you are using" if target.nil?

        attributes = ConnectorAttributes.build(manifest: manifest, target: target, values: merged_values(server, values))
        # The user's own label survives: they may have renamed the server, and an
        # update is not the place to take that back.
        server.update!(attributes.except(:name))

        # The old baseline and any drift recorded against it describe code that
        # no longer runs, so both are dropped unconditionally — keeping a warning
        # about a replaced version would be actively misleading. A fresh baseline
        # is then taken where one can be (never for stdio, which is not probed),
        # and its absence stays visible rather than being inherited.
        server.update!(tool_snapshot: {}, tool_snapshot_at: nil, tool_drift: {})
        ToolDriftDetector.capture(server)
        server
      end

      private

      def latest_manifest(connector)
        ConnectorRegistryClient.fetch(connector.name, version: connector.version.presence || "latest") ||
          connector.manifest.presence
      end

      def installed_target(server)
        server.installed_connector_target || {}
      end

      def installed_target_id(server)
        installed_target(server)["id"]
      end

      # Declared inputs present in `a` but not in `b`, compared by key.
      def input_diff(a, b)
        b_keys = Array(b["inputs"]).map { |i| i["key"] }
        Array(a["inputs"]).reject { |i| b_keys.include?(i["key"]) }
      end

      # Stored header/env values answer every input the new version still
      # declares; supplied values answer the rest and win on conflict.
      def merged_values(server, values)
        stored = (server.headers || {}).merge(server.env || {})
        stored.merge(values.to_h.stringify_keys)
      end
    end
  end
end
