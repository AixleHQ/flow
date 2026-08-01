# frozen_string_literal: true

module MCP
  # Installs a catalog connector into a project as an ordinary MCPServer.
  #
  # The manifest is RE-FETCHED from the registry at install time rather than
  # taken from the mirror. The mirror exists to make browsing and search work
  # offline; an install is a durable configuration and must not be built from a
  # copy that may be up to an hour stale. When the registry is unreachable the
  # mirrored manifest is used instead — a possibly-stale install beats refusing
  # to work while a preview-status third party is down — and the caller is told
  # which happened.
  #
  # Name collisions are resolved rather than raised on: MCPServer#name is unique
  # per project, and installing the same connector twice (or a connector whose
  # title matches a hand-authored server) is a reasonable thing to do.
  class ConnectorInstaller
    class Error < StandardError; end

    Result = Struct.new(:server, :stale, :needs_auth, keyword_init: true)

    def self.call(...) = new(...).call

    # @param connector [Connector] mirrored catalog entry
    # @param target_id [String] stable target id from the manifest
    # @param values [Hash] user-supplied input values
    # @param project [Project]
    def initialize(connector:, target_id:, values:, project:)
      @connector = connector
      @target_id = target_id
      @values = values || {}
      @project = project
    end

    def call
      manifest, stale = resolve_manifest
      target = ConnectorManifest.find_target(manifest, @target_id)
      raise Error, "That install option is no longer offered by this connector" if target.nil?

      attributes = ConnectorAttributes.build(manifest: manifest, target: target, values: @values)
      server = @project.mcp_servers.create!(attributes.merge(name: unique_name(attributes[:name])))

      # Record what the server declares, so a later change is detectable. Best
      # effort on purpose: an unreachable server (or one needing an OAuth token
      # the user has not granted yet) must not block the install, and a missing
      # baseline stays visibly missing rather than being faked as a clean one.
      #
      # The same probe answers a question the manifest cannot: whether the server
      # needs a user to sign in. A registry manifest declares the INPUTS a server
      # takes, never its auth model, so a hosted connector like Notion arrives
      # looking exactly like a public one. Asking the server settles it — an MCP
      # server that requires authorization answers 401 — which is why auth is
      # detected here rather than guessed from the shape of the manifest.
      outcome = ToolDriftDetector.capture(server)
      needs_auth = outcome.status == :unauthorized && server.auth_type_none? && !server.transport_stdio?
      server.update!(auth_type: :oauth) if needs_auth

      Result.new(server: server, stale: stale, needs_auth: needs_auth)
    rescue ConnectorAttributes::UnsupportedTargetError => e
      raise Error, "This connector cannot be installed: #{e.message}"
    end

    private

    # @return [Array(Hash, Boolean)] manifest and whether it came from the mirror
    def resolve_manifest
      live = ConnectorRegistryClient.fetch(@connector.name, version: @connector.version.presence || "latest")
      return [ live, false ] if live.present? && live["targets"].present?

      Rails.logger.warn("[ConnectorInstaller] Falling back to mirrored manifest for #{@connector.name}")
      [ @connector.manifest, true ]
    end

    # "Linear" → "Linear (2)" on the second install into the same project.
    def unique_name(name)
      base = name.presence || @connector.name
      taken = @project.mcp_servers.where("name = ? OR name LIKE ?", base, "#{base} (%)").pluck(:name)
      return base if taken.exclude?(base)

      suffix = 2
      suffix += 1 while taken.include?("#{base} (#{suffix})")
      "#{base} (#{suffix})"
    end
  end
end
