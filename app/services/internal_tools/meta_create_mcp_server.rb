# frozen_string_literal: true

module InternalTools
  class MetaCreateMCPServer < Base
    tool do
      display_name "Meta Create MCP Server"
      description "Register an MCP (Model Context Protocol) server for external tool access."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[name],
        properties: {
          env: {
            type: "object"
          },
          url: {
            type: "string",
            description: "Server endpoint URL"
          },
          name: {
            type: "string"
          },
          command: {
            type: "string",
            description: "Command for stdio transport"
          },
          headers: {
            type: "object"
          },
          transport: {
            enum: %w[http sse stdio],
            type: "string",
            description: "Default: http"
          },
          scope_type: {
            enum: %w[Project],
            type: "string"
          },
          description: {
            type: "string"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      scope_record = project

      mcp = MCPServer.create!(
        scope: scope_record,
        name: params[:name],
        description: params[:description],
        url: params[:url],
        transport: params[:transport] || "http",
        command: params[:command],
        headers: params[:headers] || {},
        env: params[:env] || {},
        kind: :custom,
        enabled: true
      )

      broadcast_meta_activity(
        action: "created_mcp_server",
        entity_type: "MCPServer",
        entity_name: mcp.name,
        entity_id: mcp.id
      )

      success({ id: mcp.id, name: mcp.name }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create MCP server: #{e.message}")
    end
  end
end
