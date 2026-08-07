# frozen_string_literal: true

module PersonalTools
  # Everything install_connector needs and nothing it does not: the install
  # targets and the inputs each one declares. Serialized through
  # ConnectorResource, the single place that knows the registry's manifest
  # dialect — a second hand-rolled reading of it here would drift from the UI's.
  class GetConnector < Base
    tool do
      display_name "Get Connector"
      description "Return one MCP connector catalog entry in full: every install target (remote endpoint " \
                  "or package, with the exact launch command) and the inputs it declares. Read this " \
                  "before install_connector — target_id and the input keys come from here."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :connector_name, type: :string,
            description: "Registry name, e.g. \"com.linear.linear\" (see search_connector_catalog).",
            required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::MCPServersPolicy, project: project)

      connector = Connector.find_by(name: params[:connector_name].to_s)
      return error("Connector '#{params[:connector_name]}' is not in the catalog") unless connector

      success(ConnectorResource.new(connector, params: { snake_keys: true }).to_h
        .merge(already_installed: installed_names(project, connector)))
    end

    private

    # Installing the same connector twice is allowed (the installer suffixes the
    # name), so this is information rather than a block — but an agent that is
    # about to add a second Linear should be able to see the first one.
    def installed_names(project, connector)
      MCPServer.visible_for_project(project).where(connector_name: connector.name).pluck(:name)
    end
  end
end
