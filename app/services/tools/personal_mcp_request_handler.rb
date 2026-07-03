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
        prompts: [ build_workflow_prompt, author_step_prompt ],
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
    # served as MCP prompts the client can pull in on demand.
    def build_workflow_prompt
      text = PersonalMCPRequestHandler.workflow_guide
      MCP::Prompt.define(
        name: "build_workflow",
        description: "How to build an Aixle workflow end-to-end: concepts, the order to call the " \
                     "workflow tools, step/sub-step structure, running and inspecting runs."
      ) do |_args, server_context: nil|
        MCP::Prompt::Result.new(
          description: "Aixle workflow building guide",
          messages: [ MCP::Prompt::Message.new(role: "user", content: { type: "text", text: text }) ]
        )
      end
    end

    def author_step_prompt
      text = PersonalMCPRequestHandler.step_guide
      MCP::Prompt.define(
        name: "author_step",
        description: "How to write a good Aixle workflow step: instructions, agent/tools/skills, " \
                     "sub-steps, dependencies, and failure handling."
      ) do |_args, server_context: nil|
        MCP::Prompt::Result.new(
          description: "Aixle step authoring guide",
          messages: [ MCP::Prompt::Message.new(role: "user", content: { type: "text", text: text }) ]
        )
      end
    end

    GUIDE_PATH = "references/aixle-system-reference.md"

    def self.workflow_guide
      path = Rails.root.join(GUIDE_PATH)
      reference = path.exist? ? path.read : "(Aixle system reference is unavailable in this environment.)"
      <<~GUIDE
        # Building an Aixle workflow

        A workflow is an ordered set of steps. Each step runs an agent in a
        container with the tools, skills, MCP servers and files you give it.
        Steps can depend on other steps (a DAG), and each step can carry
        sub-steps — a checklist the agent ticks off as it works.

        Build top-down, and prefer inspecting before mutating:

        1. `list_projects` — pick the project; every workflow tool takes its `project_id`.
        2. `list_workflows` / `get_workflow` — see what already exists before adding.
        3. `create_workflow` — name + description. Returns the `workflow_id`.
        4. For each step: `list_agents` to choose an agent, then `create_workflow_step`
           (name, instructions, agent_id, position). Set `depends_on_step_ids`
           later with `update_workflow_step` once the steps it needs exist.
        5. `create_sub_step` — break a step into a checklist when it has several
           distinct deliverables. See the `author_step` prompt for how to write
           a good step.
        6. `reorder_workflow_steps` — fix execution order by passing step ids.
        7. `trigger_workflow` — start a run (interactive or non_interactive).
           Track it with `list_workflow_runs` / `get_workflow_run`; stop one with
           `cancel_workflow_run`.

        Rules:
        - Ask the user before destructive actions (`delete_workflow`,
          `delete_workflow_step`).
        - Everything is scoped to what your account can access — a tool that
          returns "not allowed" means your role can't do that in this project.

        ---

        Platform reference:

        #{reference}
      GUIDE
    end

    def self.step_guide
      <<~GUIDE
        # Writing a good Aixle workflow step

        A step is one unit of agent work. Use `create_workflow_step` /
        `update_workflow_step`; break it into `create_sub_step` items when it has
        multiple deliverables.

        Instructions (the `instructions` field, markdown):
        - Say WHAT to do and WHAT to produce — the concrete deliverable and where
          it goes. Be specific about output files/paths.
        - Do NOT restate platform mechanics: session-completion rules, /workspace
          layout, sub-step tracking, or which tools are available. The platform
          injects those automatically — repeating them wastes context.
        - Keep it focused on this step alone; earlier steps' outputs are available
          to later steps that depend on them.

        Wiring:
        - `agent_id` (from `list_agents`) picks who runs the step.
        - `tool_ids` / `skill_ids` / `mcp_server_ids` grant capabilities — attach
          only what the step needs (list them with list_project_tools / list_skills /
          list_mcp_servers).
        - `depends_on_step_ids` builds the DAG: a step runs after every step it
          depends on. A step can't be deleted while others depend on it.

        Sub-steps:
        - One `create_sub_step` per distinct, checkable deliverable.
        - `required: false` for optional work.
        - The running agent marks them off, giving progress visibility.

        Prefer `get_workflow` to inspect the current shape before editing, and
        make one focused change per tool call.
      GUIDE
    end
  end
end
