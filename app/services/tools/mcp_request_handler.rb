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
  #   disconnected) returns an actionable in-band tool error — the tool is
  #   registered for that one request with the remedy as its handler, since the
  #   per-request server otherwise only knows available tools and would answer
  #   "tool not found".
  # - Anything outside the entitlement stays an opaque protocol error, so the
  #   remedy text cannot leak capability existence.
  class MCPRequestHandler
    def initialize(session)
      @session = session
      @ctx = Context.for_session(session)
    end

    # Returns a Rack response triple.
    #
    # Every request goes through the transport, so protocol handling is
    # entirely the gem's — envelope, version, header and lifecycle validation
    # included. Since mcp 1.2.0 the `initialize` handshake negotiates legacy
    # versions only and counter-offers its newest handshake version to anything
    # else, while a modern (SEP-2575) client carries its version in each
    # request's `_meta` envelope and gets the `resultType`/cache-hint stamps
    # that era requires. See PersonalMCPRequestHandler#call for the full note.
    #
    # The one local decision is which tool set serves this request: a call to
    # an entitled-but-disconnected tool is served by a server that registers it
    # with the remedy as its handler — see #disconnected_call_target.
    #
    # `dns_rebinding_protection: false`: see PersonalMCPRequestHandler#call —
    # the SDK default accepts only a loopback `Host` and 403s every deployed
    # request, and this endpoint is header-token authenticated, so the browser
    # rebinding it defends against cannot present a credential.
    def call(request)
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server(remedy_for: disconnected_call_target(request)),
        stateless: true, dns_rebinding_protection: false
      )
      transport.handle_request(request)
    end

    private

    attr_reader :session, :ctx

    def server(remedy_for: nil)
      tools = tool_classes
      tools += [ define_unavailable_tool(remedy_for) ] if remedy_for

      MCP::Server.new(
        name: "aixle-tools",
        tools: tools,
        server_context: { session: session }
      )
    end

    def tool_classes
      available = entitled_tools.select { |t| t.available?(ctx) && digest_intact?(t) }.sort_by(&:name)
      available.map { |row| define_tool(row) }
    end

    # Memoized per request: a tools/call resolves the entitlement twice (the
    # availability check, then the server build), and holding a pooled
    # connection for a duplicate query is what tips a busy MCP pod into
    # checkout timeouts.
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

    # The tools/call target when it names an entitled-but-unavailable tool
    # (integration disconnected), otherwise nil. Peeking at the body is only a
    # routing decision — which tool set this one request is served with — never
    # a response: answering here instead would put a result on the wire that
    # the gem never validated, and `RequestEnvelope.modern?` is deliberately
    # only a loose era classifier. `RequestEnvelope.parse!` is what rejects a
    # missing/mistyped `clientCapabilities` (-32602) or an unsupported version
    # (-32022), and the transport is what enforces the SEP-2575 header/body
    # match (-32020) and the version, Accept, content-type and session-id
    # gates. Registering the tool keeps every one of those checks in front of
    # the remedy, and lets the gem stamp `resultType` itself.
    def disconnected_call_target(request)
      return nil unless request.post?

      body = parsed_body(request)
      return nil unless body.is_a?(Hash) && body["method"] == "tools/call"

      requested = body.dig("params", "name").to_s
      tool = entitled_tools.detect { |t| t.name == requested }
      return nil if tool.nil? || tool.available?(ctx)

      tool
    end

    # The remedy, as a tool the gem dispatches: an in-band `isError` result
    # naming what to connect, produced by the same path a connected tool's
    # result takes, so the modern lifecycle's REQUIRED `resultType` (SEP-2322)
    # is the gem's stamp rather than ours and legacy results stay unstamped.
    #
    # It exists for the single tools/call that named it and is absent from
    # every tools/list, which is a different request and so a different
    # per-request server. The schema is permissive on purpose: the disconnected
    # integration is the dominant fact, so argument validation must not answer
    # in place of the remedy.
    def define_unavailable_tool(row)
      message = row.unavailable_message

      MCP::Tool.define(
        name: row.name,
        description: row.definition&.description || row.description || row.display_name,
        input_schema: { "type" => "object", "properties" => {}, "required" => [] }
      ) do |**_arguments|
        MCP::Tool::Response.new(
          CallExecutor.response_content({ exit_code: 1, stdout: "", stderr: message }), error: true
        )
      end
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
