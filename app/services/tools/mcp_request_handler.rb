# frozen_string_literal: true

require "mcp"

module Tools
  # Builds a stateless MCP::Server per authenticated request (the official
  # Ruby SDK's documented Rails idiom) from the TerminalSession's entitled
  # tool set, and hands the Rack request to the StreamableHTTP transport.
  #
  # Availability contract (unchanged from the monkey-patch era):
  # - tools/list serves only available tools, deterministically ordered, tags
  #   in _meta, MCP behavior annotations from the definition.
  # - tools/call on an entitled-but-unavailable tool (integration
  #   disconnected) returns an actionable in-band tool error — handled by a
  #   thin pre-transport shim, since the per-request server only knows
  #   available tools and would otherwise answer "tool not found".
  # - Anything outside the entitlement stays an opaque protocol error, so the
  #   remedy text cannot leak capability existence.
  class MCPRequestHandler
    MANAGED_NAMESPACE_PREFIX = "mcp__"
    MANAGED_NAMESPACE_SEPARATOR = "__"

    def initialize(session)
      @session = session
      @ctx = Context.for_session(session)
    end

    # Returns a Rack response triple.
    def call(request)
      if (response = unavailable_tool_shim(request))
        return response
      end

      transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
      transport.handle_request(request)
    end

    private

    attr_reader :session, :ctx

    def server
      @server ||= MCP::Server.new(
        name: "aixle-tools",
        tools: tool_classes,
        server_context: { session: session }
      )
    end

    def tool_classes
      entitled = session.available_tools(ctx: ctx)
      available = entitled.select { |t| t.available?(ctx) }.sort_by(&:name)
      classes = available.map { |row| define_tool(row) }

      session.mcp_servers.where(kind: "managed", enabled: true).order(:name).each do |server_row|
        managed_rows_for(server_row).each do |row|
          classes << define_tool(row, namespace: server_row.name, mcp_server: server_row)
        end
      end

      classes
    end

    def managed_rows_for(server_row)
      names = Registry.managed_tool_names(server_row.integration&.provider)
      return [] if names.empty?

      Tool.shadow_rows_for_names(names).select(&:enabled?).select { |t| t.available?(ctx) }.sort_by(&:name)
    end

    # Registry-first serialization: for code tools the in-code definition is
    # authoritative, so a stale shadow row can never serve a stale schema.
    def define_tool(row, namespace: nil, mcp_server: nil)
      defn = row.definition
      schema = (defn&.input_schema.presence || row.input_schema.presence ||
                { "type" => "object", "properties" => {}, "required" => [] })
      schema = schema.deep_stringify_keys if schema.respond_to?(:deep_stringify_keys)
      wire_name = namespace ? "#{MANAGED_NAMESPACE_PREFIX}#{namespace}#{MANAGED_NAMESPACE_SEPARATOR}#{row.name}" : row.name
      current_session = session

      MCP::Tool.define(
        name: wire_name,
        description: defn&.description || row.description || row.display_name,
        input_schema: schema,
        annotations: mcp_annotations(defn),
        meta: defn&.tags&.any? ? { "ai.aixle/tags" => defn.tags.map(&:to_s) } : nil
      ) do |server_context:, **arguments|
        result = CallExecutor.execute(row, arguments.deep_stringify_keys, current_session, mcp_server: mcp_server)
        MCP::Tool::Response.new(CallExecutor.response_content(result))
      rescue StandardError => e
        Rails.logger.error("[MCP] Tool execution failed: #{e.message}")
        MCP::Tool::Response.new([ { type: "text", text: "Tool execution failed: #{e.message}" } ], error: true)
      end
    end

    def mcp_annotations(defn)
      return nil if defn.nil? || defn.annotations.blank?

      a = defn.annotations
      MCP::Tool::Annotations.new(
        read_only_hint: a.fetch("readOnlyHint", false),
        destructive_hint: a.fetch("destructiveHint", true),
        idempotent_hint: a.fetch("idempotentHint", false),
        open_world_hint: a.fetch("openWorldHint", true)
      )
    end

    # Entitled-but-unavailable tools are hidden from the per-request server,
    # so intercept their calls before the transport and answer with an
    # actionable in-band tool error instead of "tool not found".
    def unavailable_tool_shim(request)
      return nil unless request.post?

      body = parsed_body(request)
      return nil unless body.is_a?(Hash) && body["method"] == "tools/call"

      requested = body.dig("params", "name").to_s
      base_name = strip_managed_namespace(requested)
      tool = session.available_tools(ctx: ctx).detect { |t| t.name == base_name }
      return nil if tool.nil? || tool.available?(ctx)

      result = { exit_code: 1, stdout: "", stderr: tool.unavailable_message }
      json = {
        jsonrpc: "2.0",
        id: body["id"],
        result: { content: CallExecutor.response_content(result), isError: true }
      }.to_json
      [ 200, { "Content-Type" => "application/json" }, [ json ] ]
    end

    def strip_managed_namespace(name)
      return name unless name.start_with?(MANAGED_NAMESPACE_PREFIX)

      rest = name.delete_prefix(MANAGED_NAMESPACE_PREFIX)
      idx = rest.index(MANAGED_NAMESPACE_SEPARATOR)
      idx ? rest[(idx + MANAGED_NAMESPACE_SEPARATOR.length)..] : name
    end

    def parsed_body(request)
      raw = request.body.read
      request.body.rewind
      JSON.parse(raw)
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
