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
    def call(request)
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
      transport.handle_request(request)
    end

    private

    attr_reader :user

    def server
      MCP::Server.new(
        name: "aixle",
        tools: Registry.for_audience(:user).sort_by(&:name).map { |defn| define_tool(defn) },
        prompts: [ build_workflow_prompt ],
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

    # Complex flows (building a workflow) need more guidance than tool
    # descriptions can carry — served as an MCP prompt the client can pull in.
    def build_workflow_prompt
      MCP::Prompt.define(
        name: "build_workflow",
        description: "Guide for building an Aixle workflow end-to-end with the workflow tools: " \
                     "platform concepts, step/sub-step structure, boards and triggers."
      ) do |_args, server_context: nil|
        MCP::Prompt::Result.new(
          description: "Aixle workflow building guide",
          messages: [
            MCP::Prompt::Message.new(
              role: "user",
              content: { type: "text", text: PersonalMCPRequestHandler.workflow_guide }
            )
          ]
        )
      end
    end

    GUIDE_PATH = "references/aixle-system-reference.md"

    def self.workflow_guide
      path = Rails.root.join(GUIDE_PATH)
      base = path.exist? ? path.read : "Aixle system reference is unavailable in this environment."
      <<~GUIDE
        You are building an Aixle workflow through the personal MCP tools.
        Work top-down: pick the project (list_projects), understand its board
        (board tools), then create the workflow, its steps and sub-steps, and
        only then wire triggers. Ask the user before destructive changes.

        #{base}
      GUIDE
    end
  end
end
