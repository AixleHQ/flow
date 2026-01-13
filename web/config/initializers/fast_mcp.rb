# frozen_string_literal: true

# FastMcp - Model Context Protocol for Rails
# This initializer sets up the MCP middleware in your Rails application.
#
# In Rails applications, you can use:
# - ActionTool::Base as an alias for FastMcp::Tool
# - ActionResource::Base as an alias for FastMcp::Resource
#
# All your tools should inherit from ApplicationTool which already uses ActionTool::Base,
# and all your resources should inherit from ApplicationResource which uses ActionResource::Base.

# Mount the MCP middleware in your Rails application
# You can customize the options below to fit your needs.
require "fast_mcp"

fast_mcp_config = {
  name: Settings.mcp.name,
  version: "1.0.0",
  path_prefix: "/mcp", # This is the default path prefix
  messages_route: "messages", # This is the default route for the messages endpoint
  sse_route: "sse", # This is the default route for the SSE endpoint
  # Add allowed origins below, it defaults to Rails.application.config.hosts
  # allowed_origins: ['localhost', '127.0.0.1', '[::1]', 'example.com', /.*\.example\.com/],
  localhost_only: false # Set to false to allow connections from other hosts
  # whitelist specific ips to if you want to run on localhost and allow connections from other IPs
  # allowed_ips: ['127.0.0.1', '::1']
  # authenticate: true,       # Uncomment to enable authentication
  # auth_token: 'your-token', # Required if authenticate: true
}

fast_mcp_config[:logger] = Logger.new(nil)

FastMcp.mount_in_rails(Rails.application, fast_mcp_config) do |server|
  Rails.application.config.after_initialize do
    # FastMcp will automatically discover and register:
    # - All classes that inherit from ApplicationTool (which uses ActionTool::Base)
    # - All classes that inherit from ApplicationResource (which uses ActionResource::Base)
    server.register_tools(*ApplicationTool.descendants)
    server.register_resources(*ApplicationResource.descendants)
    # alternatively, you can register tools and resources manually:
    # server.register_tool(MyTool)
    # server.register_resource(MyResource)
  end
end

module FastMcp
  class Server
    alias_method :handle_request_original, :handle_request

    def handle_request(json_str, headers: {})
      begin
        request = JSON.parse(json_str)
      rescue JSON::ParserError, TypeError
        return send_error(-32_600, "Invalid Request", nil)
      end

      keep_alive_notification = request["method"].blank?
      log_request(request, headers) unless keep_alive_notification

      handle_request_original(json_str, headers: headers)
    end

    def log_request(request, headers)
      auth_token = headers["auth-token"] || nil
      spec_user = SpecificationUser.find_by(mcp_token: auth_token)
      data = {
        method: "SSE",
        path: "/mcp/sse",
        format: "json",
        controller: "MCP",
        action: request["method"],
        params: request["params"] || {},
        id: request["id"],
        user_id: spec_user&.user_id,
        specification_id: spec_user&.specification_id
      }

      if Rails.configuration.lograge.enabled
        lograge_data = Lograge.formatter.call(data)
        Rails.logger.info(lograge_data)
      end
    end
  end
end
