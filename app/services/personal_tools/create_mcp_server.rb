# frozen_string_literal: true

module PersonalTools
  class CreateMCPServer < Base
    tool do
      display_name "Create MCP Server"
      description "Register a custom MCP server in a project."
      audience :user
      tags :resources
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Server name (identifier).", required: true
      param :display_name, type: :string, description: "Human-readable name."
      param :url, type: :string, description: "Server URL (http/sse transports)."
      param :transport, type: :string, description: "Transport.", enum: %w[http sse stdio]
      param :command, type: :string, description: "Command (stdio transport)."
      param :description, type: :string, description: "What the server provides."
    end

    ATTRS = %w[name display_name url transport command description].freeze

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::MCPServersPolicy, project: project)
      attrs = params.slice(*ATTRS).compact
      attrs["display_name"] ||= attrs["name"]
      server = project.mcp_servers.create!(attrs.merge(kind: :custom))
      success(id: server.id, name: server.name, kind: server.kind, transport: server.transport)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create MCP server: #{e.message}")
    end
  end
end
