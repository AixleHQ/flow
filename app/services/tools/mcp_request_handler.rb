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
    def initialize(session)
      @session = session
      @ctx = Context.for_session(session)
    end

    # Returns a Rack response triple.
    #
    # The server is configured with the newest protocol version it can serve
    # and the offered version is capped before the transport sees it — see
    # MCPProtocol — so the handshake can only agree to a version whose result
    # shapes this server actually produces.
    #
    # `dns_rebinding_protection: false`: see PersonalMCPRequestHandler#call —
    # the SDK default accepts only a loopback `Host` and 403s every deployed
    # request, and this endpoint is header-token authenticated, so the browser
    # rebinding it defends against cannot present a credential.
    def call(request)
      MCPProtocol.clamp_initialize_offer!(request)

      if (response = unavailable_tool_shim(request))
        return response
      end

      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server, stateless: true, dns_rebinding_protection: false
      )
      transport.handle_request(request)
    end

    private

    attr_reader :session, :ctx

    def server
      @server ||= MCP::Server.new(
        name: "aixle-tools",
        configuration: MCPProtocol.configuration,
        tools: tool_classes,
        server_context: { session: session }
      )
    end

    def tool_classes
      available = entitled_tools.select { |t| t.available?(ctx) && digest_intact?(t) }.sort_by(&:name)
      available.map { |row| define_tool(row) }
    end

    # Memoized per request: a tools/call resolves the entitlement twice (the
    # shim, then the server build), and holding a pooled connection for a
    # duplicate query is what tips a busy MCP pod into checkout timeouts.
    def entitled_tools
      @entitled_tools ||= session.available_tools(ctx: ctx)
    end

    # Fail closed on tampered custom definitions: a tools row written past the
    # model's validation+digest pipeline (update_columns, raw SQL) is a
    # potential rug pull — drop it from serving and make noise.
    def digest_intact?(tool)
      return true if tool.definition_digest_intact?

      Rails.logger.error(
        "[MCP] Custom tool ##{tool.id} (#{tool.name}) failed the definition digest check — " \
        "hidden from serving. Re-save it through validations to re-publish."
      )
      false
    end

    # Registry-first serialization: for code tools the in-code definition is
    # authoritative, so a stale shadow row can never serve a stale schema.
    def define_tool(row)
      defn = row.definition
      schema = (defn&.input_schema.presence || row.input_schema.presence ||
                { "type" => "object", "properties" => {}, "required" => [] })
      schema = schema.deep_stringify_keys if schema.respond_to?(:deep_stringify_keys)
      current_session = session

      MCP::Tool.define(
        name: row.name,
        description: defn&.description || row.description || row.display_name,
        input_schema: schema,
        annotations: mcp_annotations(defn),
        meta: defn&.tags&.any? ? { "ai.aixle/tags" => defn.tags.map(&:to_s) } : nil
      ) do |server_context:, **arguments|
        result = CallExecutor.execute(row, arguments.deep_stringify_keys, current_session)
        MCP::Tool::Response.new(CallExecutor.response_content(result))
      rescue StandardError => e
        Rails.logger.error("[MCP] Tool execution failed: #{e.message}")
        MCP::Tool::Response.new([ { type: "text", text: "Tool execution failed: #{e.message}" } ], error: true)
      end
    end

    def mcp_annotations(defn)
      return nil if defn.nil? || defn.annotations.blank?

      a = defn.annotations
      {
        read_only_hint: a.fetch("readOnlyHint", false),
        destructive_hint: a.fetch("destructiveHint", true),
        idempotent_hint: a.fetch("idempotentHint", false),
        open_world_hint: a.fetch("openWorldHint", true)
      }
    end

    # Entitled-but-unavailable tools are hidden from the per-request server,
    # so intercept their calls before the transport and answer with an
    # actionable in-band tool error instead of "tool not found".
    def unavailable_tool_shim(request)
      return nil unless request.post?

      body = parsed_body(request)
      return nil unless body.is_a?(Hash) && body["method"] == "tools/call"

      requested = body.dig("params", "name").to_s
      tool = entitled_tools.detect { |t| t.name == requested }
      return nil if tool.nil? || tool.available?(ctx)

      result = { exit_code: 1, stdout: "", stderr: tool.unavailable_message }
      json = {
        jsonrpc: "2.0",
        id: body["id"],
        result: { content: CallExecutor.response_content(result), isError: true }
      }.to_json
      [ 200, { "Content-Type" => "application/json" }, [ json ] ]
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
