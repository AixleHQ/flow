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
          scope_id: {
            type: "integer"
          },
          transport: {
            enum: %w[http sse stdio],
            type: "string",
            description: "Default: http"
          },
          scope_type: {
            enum: %w[Project Company],
            type: "string"
          },
          description: {
            type: "string"
          },
          display_name: {
            type: "string"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      scope_type = params[:scope_type] || "Company"
      scope_id = params[:scope_id]

      case scope_type
      when "Project"
        scope_id ||= target_project&.id
        scope_record = Project.find(scope_id)
      when "Company"
        scope_id ||= target_project&.company_id
        scope_record = Company.find(scope_id)
      else
        return error("Invalid scope_type: #{scope_type}")
      end

      mcp = MCPServer.create!(
        scope: scope_record,
        name: params[:name],
        display_name: params[:display_name] || params[:name].titleize,
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
        entity_name: mcp.display_name,
        entity_id: mcp.id
      )

      success({ id: mcp.id, name: mcp.name, display_name: mcp.display_name }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create MCP server: #{e.message}")
    end
  end
end
