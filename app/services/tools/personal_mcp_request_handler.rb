# frozen_string_literal: true

require "mcp"

module Tools
  # The personal (session-less) MCP server: authenticated by a user's
  # amcp_ token, serves every registry tool with `audience :user` — the
  # user-level surface over Aixle (companies, projects, boards, workflows,
  # ...). No shadow rows, no session: handlers run straight from the registry
  # with (params, user), and every data access inside them goes through the
  # same policies as the UI.
  class PersonalMCPRequestHandler
    def initialize(user)
      @user = user
    end

    # Returns a Rack response triple.
    #
    # The server is configured with the newest protocol version it can serve
    # and the offered version is capped before the transport sees it — see
    # MCPProtocol — so the handshake can only agree to a version whose result
    # shapes this server actually produces.
    #
    # `dns_rebinding_protection: false`: the SDK's own default only accepts a
    # loopback `Host`, which 403s every request to a deployed host. The
    # protection it provides is aimed at localhost servers a browser can reach
    # with implicit trust — this endpoint authenticates from an amcp_ token in
    # a header, never a cookie, so a rebound browser request arrives without a
    # credential and is answered with 401.
    def call(request)
      MCPProtocol.clamp_initialize_offer!(request)

      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server, stateless: true, dns_rebinding_protection: false
      )
      transport.handle_request(request)
    end

    private

    attr_reader :user

    def server
      MCP::Server.new(
        name: "aixle",
        configuration: MCPProtocol.configuration,
        instructions: PersonalMCPGuides::INSTRUCTIONS,
        tools: Registry.for_audience(:user).sort_by(&:name).map { |defn| define_tool(defn) },
        prompts: PROMPTS.map { |spec| define_prompt(spec) },
        resources: [ reference_resource ],
        server_context: { user: user }
      )
    end

    def define_tool(defn)
      current_user = user

      MCP::Tool.define(
        name: defn.name,
        description: defn.description,
        input_schema: defn.input_schema,
        annotations: mcp_annotations(defn),
        meta: defn.tags.any? ? { "ai.aixle/tags" => defn.tags.map(&:to_s) } : nil
      ) do |server_context:, **arguments|
        handler = defn.handler_class.new(params: arguments.deep_stringify_keys, user: current_user)
        result = handler.execute
        MCP::Tool::Response.new(
          CallExecutor.response_content(result),
          error: (result[:exit_code] || result["exit_code"]) != 0
        )
      rescue PersonalTools::Base::UnauthorizedError, PersonalTools::Base::NotFoundError => e
        MCP::Tool::Response.new([ { type: "text", text: e.message } ], error: true)
      rescue StandardError => e
        Rails.logger.error("[PersonalMCP] #{defn.name} failed: #{e.message}")
        MCP::Tool::Response.new([ { type: "text", text: "Tool execution failed: #{e.message}" } ], error: true)
      end
    end

    def mcp_annotations(defn)
      return nil if defn.annotations.blank?

      a = defn.annotations
      {
        read_only_hint: a.fetch("readOnlyHint", false),
        destructive_hint: a.fetch("destructiveHint", true),
        idempotent_hint: a.fetch("idempotentHint", false),
        open_world_hint: a.fetch("openWorldHint", true)
      }
    end

    # Complex flows need more guidance than tool descriptions can carry —
    # served as MCP prompts the client pulls in on demand. `guide` names the
    # PersonalMCPGuides method, called inside the block so nothing is rendered
    # until a client actually asks for that prompt.
    PROMPTS = [
      { name: "setup_project", guide: :setup_project, title: "Aixle project setup guide",
        description: "How to take an Aixle project from nothing to a running workflow: company and " \
                     "project, integrations, repositories, secrets, tools/skills/MCP servers, agents, " \
                     "the board, then the workflow and its trigger." },
      { name: "build_workflow", guide: :build_workflow, title: "Aixle workflow building guide",
        description: "How to build an Aixle workflow end-to-end: concepts, the order to call the " \
                     "workflow tools, step/sub-step structure, running and inspecting runs." },
      { name: "author_step", guide: :author_step, title: "Aixle step authoring guide",
        description: "How to write a good Aixle workflow step: instructions, agent/tools/skills, " \
                     "sub-steps, dependencies, and failure handling." },
      { name: "tool_catalog", guide: :tool_catalog, title: "Aixle tool catalog",
        description: "Every tool this server exposes, grouped by area (account, integrations, project " \
                     "resources, board, workflows) with a one-line summary each." }
    ].freeze

    def define_prompt(spec)
      MCP::Prompt.define(name: spec[:name], description: spec[:description]) do |_args, server_context: nil|
        MCP::Prompt::Result.new(
          description: spec[:title],
          messages: [ MCP::Prompt::Message.new(
            role: "user", content: { type: "text", text: PersonalMCPGuides.public_send(spec[:guide]) }
          ) ]
        )
      end
    end

    # The full domain model, served as a resource rather than inlined into a
    # prompt: it is ~500 lines and only some callers ever need it.
    def reference_resource
      MCP::Resource.define(
        uri: PersonalMCPGuides::REFERENCE_URI,
        name: "aixle-system-reference",
        description: "The Aixle platform reference: entities and their relationships, scoping, " \
                     "triggers and automation, agent runtimes and the container a step executes in.",
        mime_type: "text/markdown"
      ) do
        MCP::Resource::TextContents.new(
          uri: PersonalMCPGuides::REFERENCE_URI,
          mime_type: "text/markdown",
          text: PersonalMCPGuides.system_reference
        )
      end
    end
  end
end
