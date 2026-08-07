# frozen_string_literal: true

module PersonalTools
  # The catalog install path, as the web Connectors controller performs it.
  # A connector is not a resource of its own — it is a pre-described way to
  # create an MCPServer — so this returns the server it created.
  class InstallConnector < Base
    tool do
      display_name "Install Connector"
      description "Install an MCP connector from the catalog into a project as an MCP server. " \
                  "Read the entry with get_connector first: target_id picks which install option to use, " \
                  "and values answers the inputs that target declares."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :connector_name, type: :string, description: "Registry name (see search_connector_catalog).",
            required: true
      param :target_id, type: :string,
            description: "Install target id from get_connector. Omit to use the connector's only " \
                         "supported target; required when it offers several.",
            required: false
      param :values, type: :object,
            description: "Answers to the target's declared inputs, keyed by the input's `key` verbatim " \
                         "(header names and env vars are case- and punctuation-sensitive)."
    end

    # Raised when the caller named no target and the manifest does not settle it
    # on its own — the message names what to do instead.
    class TargetSelectionError < StandardError; end

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::MCPServersPolicy, project: project)

      connector = Connector.find_by(name: params[:connector_name].to_s)
      return error("Connector '#{params[:connector_name]}' is not in the catalog") unless connector

      install(connector, params[:target_id].presence || sole_target_id!(connector), project)
    rescue TargetSelectionError => e
      error(e.message)
    rescue MCP::ConnectorInstaller::Error => e
      error("Install failed: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      error("Install failed: #{e.record.errors.full_messages.join(', ')}")
    end

    private

    def install(connector, target_id, project)
      result = MCP::ConnectorInstaller.call(
        connector: connector, target_id: target_id, values: string_values, project: project
      )
      server = result.server

      success(id: server.id, name: server.name, transport: server.transport,
              connector_name: server.connector_name, connector_version: server.connector_version,
              # The registry was unreachable, so the install was built from the
              # mirrored manifest, which can be up to an hour stale.
              installed_from_mirror: result.stale,
              # Detected, not guessed: the server answered 401. An installed but
              # unauthenticated connector looks identical to a working one until an
              # agent tries to use it, so say it plainly and name the next action.
              needs_auth: result.needs_auth,
              next_step: result.needs_auth ? "Sign in to this server from the project's MCP servers page — " \
                                             "OAuth needs a browser and cannot be completed over MCP." : nil)
    end

    # Unsupported targets travel with a reason, so an agent that picked nothing
    # gets told why rather than "not found".
    def sole_target_id!(connector)
      targets = Array(connector.manifest["targets"])
      supported = targets.select { |t| t["supported"] == true }
      return supported.first["id"] if supported.one?

      raise TargetSelectionError, unsupported_message(targets) if supported.empty?

      raise TargetSelectionError,
            "This connector offers #{supported.size} install targets — pass target_id " \
            "(#{supported.map { |t| t['id'] }.join(', ')}); see get_connector."
    end

    def unsupported_message(targets)
      reasons = targets.filter_map { |t| t["unsupported_reason"] }.uniq
      return "This connector has no installable target" if reasons.empty?

      "This connector cannot be installed: #{reasons.join('; ')}"
    end

    # Inputs are wired into headers, env vars and argv, all of which are strings.
    # Coerce here so a JSON number or boolean does not reach the manifest layer
    # as a non-string and fail to match its declared input.
    def string_values
      (params[:values] || {}).each_with_object({}) do |(key, value), memo|
        next if value.nil? || value.is_a?(Hash)

        memo[key.to_s] = value.is_a?(Array) ? value.map(&:to_s) : value.to_s
      end
    end
  end
end
