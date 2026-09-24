# frozen_string_literal: true

module PersonalTools
  class UpdateMCPServer < Base
    tool do
      display_name "Update MCP Server"
      description "Update a custom MCP server. Managed servers cannot be edited. Changing url, transport or " \
                  "command to a new address clears the server's stored header and env values and its OAuth " \
                  "connections; a person re-enters them in the MCP servers page."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :mcp_server_id, type: :integer, description: "MCP server id.", required: true
      param :url, type: :string, description: "URL."
      param :transport, type: :string, description: "Transport.", enum: %w[http sse stdio]
      param :command, type: :string, description: "Command."
      param :description, type: :string, description: "Description."
      param :enabled, type: :boolean, description: "Enabled flag."
    end

    ATTRS = %w[url transport command description enabled].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::MCPServersPolicy, project: project)
      server = project.mcp_servers.where(kind: :custom).find_by(id: params[:mcp_server_id])
      return error("Custom MCP server not found in this project") unless server

      attrs = params.slice(*ATTRS).reject { |_, v| v.nil? }
      return error("No fields to update") if attrs.empty?

      server.assign_attributes(attrs)
      moved = server.destination_changed?
      server.save!
      success(id: server.id, name: server.name, updated_fields: attrs.keys, secrets_cleared: moved)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update MCP server: #{e.message}")
    end
  end
end
