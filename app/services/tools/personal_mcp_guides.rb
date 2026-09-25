# frozen_string_literal: true

module Tools
  # Everything the personal MCP server says about itself: the always-on
  # `instructions` block returned from `initialize`, the four on-demand prompts,
  # and the platform reference served as a resource.
  #
  # Split from PersonalMCPRequestHandler so that file stays wiring. The
  # division of labour between the three surfaces:
  #
  # - `INSTRUCTIONS` — in the client's context on every connection, so it holds
  #   only what a caller must know BEFORE its first call: the entity shape, the
  #   rules that prevent damage, and where the rest lives.
  # - prompts — pulled deliberately, one per flow, so they can be long.
  # - the reference resource — the full domain model, read when a prompt isn't
  #   enough. Not inlined into a prompt: it is ~500 lines, half of them about
  #   the in-container session runtime a personal-token caller never sees.
  module PersonalMCPGuides
    REFERENCE_PATH = "references/aixle-system-reference.md"
    REFERENCE_URI = "aixle://reference/system"

    INSTRUCTIONS = <<~TEXT
      Aixle runs business processes as workflows: ordered steps executed by AI
      agents in containers, launched by hand or by a trigger. This server is
      your personal Aixle account — every call runs as you, with your own
      permissions, across every company you belong to. There is no "current
      project": nearly every tool takes an explicit `project_id`.

      The shape of the world:

        Company -> Projects. A project owns a board (columns + tasks), its
        workflows (steps -> sub-steps), and the resources steps draw on: agents,
        tools, skills, MCP servers, repositories, config items, assets. All of
        them belong to one project — only assets can also be company-wide — so
        an id from one project never works in another.

      How to work here:

      - Start from `list_companies` / `list_projects`. Every id you pass comes
        from a list tool — never invent one, never carry an id across projects.
      - Read before you write: `get_workflow`, `get_workflow_step`, `get_agent`,
        `get_skill`, `get_mcp_server`. `get_workflow` carries step instructions
        in full; `get_workflow_step` adds one step's remaining wiring.
      - Every id list on an update (`tool_ids`, `skill_ids`, `mcp_server_ids`,
        `depends_on_step_ids`, the workflow's `base_*` lists) REPLACES the
        current one. Read the current value first, then send the whole list.
      - Ask the user before anything destructive: every `delete_*`,
        `uninstall_skill`, `cancel_workflow_run`, `skip_step_run`, `stop_session`.
      - A run that has gone quiet: `list_sessions` finds the session, then
        `get_session_log` shows its terminal tail, how long it has been silent
        (`idle_seconds`) and whether it hit a provider quota. Long silence is
        not proof of a hang — an agent thinking, or waiting on a slow tool, also
        looks silent. To put a board task's automation back to the start:
        `stop_session` on what is stuck, then `trigger_task_workflow` (its
        `force` does the cancel for you).
      - Secrets never travel over this server. Config item values are
        write-only and come back masked, MCP header/env values are never
        returned, and integrations are connected by the user in the browser
        (`get_integration_setup_url`).
      - Installing from a public catalog (`install_connector`, `install_skill`)
        puts third-party code or prompt text into a project. Read the entry
        first (`get_connector`, `get_registry_skill`) and confirm with the user.
      - "Not allowed" means your role lacks that permission in that project.
        Retrying will not help — tell the user what needs granting.

      More detail, on demand:

      - prompt `setup_project` — a project from nothing to a running workflow.
      - prompt `build_workflow` — workflow concepts and the order to call the
        workflow tools.
      - prompt `author_step` — how to write a step an agent can actually run.
      - prompt `tool_catalog` — every tool on this server, grouped by area.
      - prompt `publish_template` — turn a working project into a catalog pull request.
      - resource `#{REFERENCE_URI}` — the full platform reference.
    TEXT

    # Tag -> how the tool catalog presents that slice of the registry. The tags
    # come from the tool definitions themselves, so a new tool joins its group
    # with no edit here.
    CATALOG_GROUPS = [
      { tag: :account, title: "Account & projects",
        blurb: "Where every flow starts — these return the ids the other tools take." },
      { tag: :integrations, title: "Integrations",
        blurb: "Connection status, and the browser URL where the user connects one. " \
               "Credentials are never handled over MCP." },
      { tag: :resources, title: "Project resources",
        blurb: "What a workflow step can be given: agents, tools, skills, MCP servers, " \
               "repositories, config items, assets — plus the public catalogs to install from." },
      { tag: :board, title: "Board",
        blurb: "Columns and tasks. A new project has no board at all until `setup_board` " \
               "creates one, and moving a card is what fires a column trigger." },
      { tag: :templates, title: "Templates",
        blurb: "Ready-made connectors, boards, workflows and projects from the reviewed public catalog, " \
               "and turning a working setup into a catalog pull request." },
      { tag: :workflows, title: "Workflows & runs",
        blurb: "Define workflows and their steps, attach triggers, then start runs and " \
               "diagnose them." },
      { tag: :sessions, title: "Agent sessions",
        blurb: "The containers a run actually executes in: what they are printing right now, " \
               "how long they have been silent, and how to stop one." }
    ].freeze

    class << self
      def system_reference
        path = Rails.root.join(REFERENCE_PATH)
        return "(Aixle system reference is unavailable in this environment.)" unless path.exist?

        path.read
      end

      # Generated from the live registry: adding a tool updates the catalog,
      # and a tool that carries no known tag still shows up (under "Other")
      # rather than silently vanishing from the map. `defs` is what the caller
      # is actually serving — a user who has switched tools off must not be
      # handed a catalog advertising them.
      def tool_catalog(defs = Registry.for_audience(:user))
        sections = catalog_sections(defs)

        <<~TEXT
          # Aixle tools on this server

          Every tool your token can call, grouped by area, one line each —
          generated from the live registry. Full parameter schemas are in
          `tools/list`; the flows these tools serve are in the `setup_project`,
          `build_workflow` and `author_step` prompts.

          #{sections.join("\n").rstrip}

          Two rules worth repeating, because they are what usually goes wrong:
          read a workflow step before editing it, and remember that an id list
          on an update replaces the current one wholesale.
        TEXT
      end

      def catalog_sections(defs)
        known = CATALOG_GROUPS.map { |g| g[:tag] }
        sections = CATALOG_GROUPS.filter_map do |group|
          section(group[:title], group[:blurb], defs.select { |d| d.tags.include?(group[:tag]) })
        end
        sections << section("Other", nil, defs.reject { |d| d.tags.intersect?(known) })
        sections.compact
      end

      def publish_template
        <<~GUIDE
          # Publishing a working setup to the Aixle Flow template catalog

          The catalog is the public repository #{Templates::RepositoryClient::REPOSITORY}
          (branch `#{Templates::RepositoryClient::BRANCH}`). A template is published by a pull
          request that the Flow maintainers review; every Flow installation mirrors the
          repository within the hour after merge. Flow itself never writes to the
          repository — you open the pull request with the user's own GitHub access.

          ## 1. Choose what to publish

          Ask the user which project, and whether it is the whole project (board +
          workflows), only some workflows, or a single agent or skill. A whole-project
          template always installs as a new project; anything else can be added to an
          existing project. For an agent or skill, export with `workflow_ids: []`,
          `include_board: false` and `agent_ids` / `skill_ids`.
          Agree on a slug (lowercase words joined by dashes), a name and a one-line summary.

          Every template lives under a publisher **namespace**, and its catalog id is
          `namespace/slug`. Check `namespaces.yaml` in the repository: if the user
          already owns a namespace (their GitHub login is in its `owners`), use it.
          Otherwise add an entry for a new one in the same pull request —
          `name` (usually their GitHub login), `display_name`, `owners: [<login>]` —
          and leave `verified` out; only the maintainers set it. A pull request that
          changes a namespace its author does not own fails CI.

          ## 2. Export

          Call `export_template` with the project, slug and name (`workflow_ids`,
          `include_board`, `include_assets` as agreed). If it refuses, show the user
          each reason and fix it in the project first — typically a literal MCP header
          value that must become a config item (`config_item:NAME`), or a tool image
          that must be pinned by digest (`image@sha256:…`). Never edit the exported
          package to smuggle a literal secret back in.

          ## 3. Make it portable — walk through this with the user

          - Every exported `variables` entry carries its current value. For each one,
            ask whether it is specific to this project (an org slug, a channel, a
            branch). If so, add an `inputs` entry and replace the value with
            `{{inputs.<key>}}`. Inputs are only substituted in instructions, agent
            text, column purposes, workflow descriptions, custom MCP url/args/headers/env,
            trigger cron and title templates, and variable values.
          - Read every step's instructions and agent persona for names, URLs or ids
            that only make sense in this project; generalise them or turn them into inputs.
          - Write `README.md` (what it does, who it is for) and `SETUP.md` (what to do
            after installing: which integrations to connect, which secrets to add,
            which repository to attach). `SETUP.md` is required when `requires` is not empty.
          - Keep the exported `version: 1` for a new template. Updating an existing
            template means increasing `version` by one.

          ## 4. Open the pull request

          1. Fork #{Templates::RepositoryClient::REPOSITORY} (or branch, if the user has write access).
          2. Write `templates/<namespace>/<slug>/template.yaml` from `template_yaml`, and
             every entry of `files` next to it (`content` as text, `base64` decoded).
          3. Run the repository's validator (`bin/validate`) and fix what it reports.
          4. Commit, push, and open the pull request against `#{Templates::RepositoryClient::BRANCH}`.
             In the description say what the template does, what it installs, and
             what it needs after install. Mention any third-party container images.
          5. Give the user the pull request URL.

          The maintainers review the pull request; after merge the template appears in
          the catalog on the next hourly sync.
        GUIDE
      end

      def setup_project
        <<~GUIDE
          # Setting up an Aixle project from scratch

          Order matters: each stage needs ids or connections the earlier ones
          create. Carry the `project_id` from stage 1 into every later call.

          ## 1. Company, then project
          - `list_companies` — your active memberships and your role in each.
          - `create_project` — name + description; pass `company_id` when you
            belong to more than one company. Returns the `project_id`.
          - `update_project_settings` — name, description, artifacts language,
            state.
          - `list_project_members` — who can reach the project; their ids are
            what a board task's assignee takes.

          ## 2. Integrations, before anything that depends on them
          - `list_integrations` — GitHub / GitLab / Slack / Coder and whether
            each is connected.
          - Missing one? `get_integration_setup_url` returns the settings page;
            the user connects it in the browser. Credentials never come through
            MCP.
          - A git integration gates private repositories; Slack gates a Slack
            trigger. Connect them now rather than half-way through.

          ## 3. Repositories
          - `create_repository` — `full_name` + `integration_id` for a repo the
            app is installed on, or `public_url` for a public one (attached
            read-only and cloned without credentials, so no integration is
            needed). Requires company admin.
          - `list_repositories` / `update_repository` — branch, purpose,
            description.

          ## 4. Config items (the only place secrets live)
          - `create_config_item` — `secret` is stored encrypted, `variable` is
            plain text.
          - MCP server headers and env values reference a config item by key
            instead of carrying the secret. `list_config_items` masks values,
            and nothing ever reads one back.

          ## 5. Capabilities the steps will use
          - Tools: `list_project_tools` (attachable platform tools plus the
            project's own). `create_custom_tool` adds a docker-image tool.
          - MCP servers: `list_mcp_servers`. Add from the public catalog with
            `search_connector_catalog` -> `get_connector` -> `install_connector`,
            or register one by hand with `create_mcp_server`.
          - Skills: `list_skills`. Add from the registry with
            `search_skill_registry` -> `get_registry_skill` -> `install_skill`,
            or write your own with `create_skill` (SKILL.md content; the
            frontmatter needs a name and a description).
          - Files: `list_assets` shows what the project already has to work
            with.
          - Read the entry before installing anything: a connector's install
            target decides what actually runs, and a skill's SKILL.md is prompt
            text your agents will follow.

          ## 6. Agents
          - `list_agents` — the project's agents.
          - `create_agent` — the persona a step runs as. `get_agent` reads one
            in full before you reuse it.

          ## 7. The board
          - A new project has NO board, and every other board tool fails until
            it exists. `setup_board` creates one from a preset:
            `simple_kanban` (3 columns), `dev_team` (7), `full_sdlc` (19).
          - `list_board_columns`, `create_board_column`, `update_board_column`,
            `reorder_board_columns`, `delete_board_column` shape it (all
            project-admin). A column with tasks cannot be deleted.
          - `create_board_task` puts work on it; `move_board_task` between
            columns is what a column trigger reacts to.
          - `archive_board_task` takes a card off the board reversibly (and
            puts it back with `archived: false`); `delete_board_task` destroys
            it with its comments, assets and gates. Archive unless the user
            asked to delete.

          ## 8. The workflow
          - Read the `build_workflow` prompt for the full sequence and
            `author_step` for writing one step. In short: `create_workflow` ->
            `create_workflow_step` per unit of work (agent + wiring in the same
            call) -> `create_sub_step` for checklists ->
            `reorder_workflow_steps`.

          ## 9. Automation
          - `create_workflow_trigger` with a `kind`: `column` (a card entering a
            board column — the column must already exist), `slack`, `schedule`
            (cron AND an explicit timezone, or Temporal schedules in UTC and
            drifts under daylight saving), `webhook` (returns the endpoint URL
            and a secret shown only in that response), or `event`.
          - The off-board kinds fire with nobody watching, so every step needs
            `allow_non_interactive` first — otherwise the trigger is rejected
            and the error names the steps.

          ## 10. Run it, then read the run
          - `trigger_workflow` starts one by hand. `list_workflow_runs` /
            `get_workflow_run` report state; `get_step_run` is what explains a
            failure (error category, retries, session diagnostics).
          - `approve_step_run`, `retry_step_run`, `skip_step_run` and
            `cancel_workflow_run` drive a run in flight.

          Shortcut: if a workflow elsewhere already does most of the job,
          `duplicate_workflow` copies it — steps, sub-steps and wiring — into
          this project. It returns a `needs_setup` list, because secrets,
          assets, repositories and integrations are never copied.
        GUIDE
      end

      def build_workflow
        <<~GUIDE
          # Building an Aixle workflow

          A workflow is an ordered set of steps. Each step runs an agent in a
          container with the tools, skills, MCP servers and files you give it.
          Steps can depend on other steps (a DAG), and each step can carry
          sub-steps — a checklist the agent ticks off as it works.

          Build top-down, and prefer inspecting before mutating:

          1. `list_projects` — pick the project; every workflow tool takes its `project_id`.
          2. `list_workflows` / `get_workflow` — see what already exists before adding.
             `get_workflow` also reports the workflow's base resources (tools, skills
             and MCP servers every step gets) — read them before wiring per-step ones.
          3. `create_workflow` — name + description. Returns the `workflow_id`.
             `update_workflow` renames it and sets the base resources.
             `duplicate_workflow` copies an existing one, into this project or another.
          4. Inspect what you can wire in: `list_project_tools`, `list_skills`,
             `list_mcp_servers`, `list_agents`. `get_agent`, `get_skill` and
             `get_mcp_server` return the full persona / skill content / server wiring
             when the list entry isn't enough to decide. Nothing suitable in the
             project yet? Add it from the public catalogs first:
             `search_connector_catalog` → `get_connector` → `install_connector` for
             MCP servers, `search_skill_registry` → `get_registry_skill` →
             `install_skill` for skills. Read the entry before installing — a
             connector's install target decides what runs, and a skill's SKILL.md is
             prompt text your agents will follow.
          5. For each step: `create_workflow_step` takes the wiring in one call —
             name, instructions, agent_id, position, plus `tool_ids`, `skill_ids`,
             `mcp_server_ids`, `depends_on_step_ids`, `bmad_enabled` and
             `allow_non_interactive`. Dependencies must already exist, so create
             the steps they point at first (or set them later with
             `update_workflow_step`).
          6. `create_sub_step` — break a step into a checklist when it has several
             distinct deliverables. `update_sub_step` / `delete_sub_step` /
             `reorder_sub_steps` edit, remove and reorder them; all take the
             `sub_step_id`s reported by `get_workflow_step`. See the `author_step`
             prompt for how to write a good step.
          7. `reorder_workflow_steps` — fix execution order by passing step ids.
          8. Connect a trigger, or the workflow only ever starts by hand:
             `create_workflow_trigger` with a `kind` —
             `column` (a card entering a board column), `slack` (an inbound message),
             `schedule` (cron), `webhook` (an inbound HTTP call, which also returns the
             endpoint URL and secret), or `event` (a custom platform event).
             `list_workflow_triggers` / `update_workflow_trigger` /
             `delete_workflow_trigger` manage them.
          9. `trigger_workflow` — start a run by hand (interactive or non_interactive).
             Track it with `list_workflow_runs` / `get_workflow_run`; read a single
             step run's error, retries and session diagnostics with `get_step_run`;
             stop a run with `cancel_workflow_run`.

          Rules:
          - Ask the user before destructive actions (`delete_workflow`,
            `delete_workflow_step`, `delete_sub_step`, `delete_workflow_trigger`).
          - Read a step (`get_workflow`, or `get_workflow_step` for its full
            wiring) before editing it, or you will overwrite text you never saw.
            The same applies to every id list (`tool_ids`, `skill_ids`,
            `mcp_server_ids`, `depends_on_step_ids`, and the workflow's `base_*`
            lists): an update REPLACES the list, so read the current value first.
          - The off-board trigger kinds (slack, schedule, webhook, event) fire with
            nobody watching, so every step must have `allow_non_interactive` set.
            A trigger whose workflow still has a human-gated step is rejected on
            save, and the error names the steps.
          - A `schedule` trigger needs a cron expression AND an explicit timezone —
            leave the timezone out and Temporal schedules in UTC, which drifts by an
            hour under daylight saving.
          - Everything is scoped to what your account can access — a tool that
            returns "not allowed" means your role can't do that in this project.

          Starting from an empty project instead of an existing one? The
          `setup_project` prompt covers what has to exist first. The full domain
          model — entities, scoping, the container runtime a step executes in —
          is the `#{REFERENCE_URI}` resource.
        GUIDE
      end

      def author_step
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
          - `agent_id` (from `list_agents`) picks who runs the step. `get_agent`
            returns that agent's full persona when the title isn't enough.
          - `required_agent_runtime` pins the step to one of
            #{Step::SUPPORTED_AGENT_RUNTIMES.map { |r| "`#{r}`" }.join(', ')}. Pass null
            in `update_workflow_step` to return to normal runtime resolution.
          - `tool_ids` / `skill_ids` / `mcp_server_ids` grant capabilities — attach
            only what the step needs (list them with list_project_tools / list_skills /
            list_mcp_servers, and read a skill's content with `get_skill` before
            deciding). Check the workflow's `base_*` lists in `get_workflow` first:
            those already apply to every step, so don't re-attach them here.
          - `depends_on_step_ids` builds the DAG: a step runs after every step it
            depends on. A step can't be deleted while others depend on it.
          - `allow_non_interactive` lets the step run unattended. Every step needs it
            before a slack / schedule / webhook trigger can be attached to the
            workflow.
          - Each of those id lists is REPLACED wholesale by an update — read the
            current value with `get_workflow_step` before changing one.

          Sub-steps:
          - One `create_sub_step` per distinct, checkable deliverable.
          - `required: false` for optional work.
          - The running agent marks them off, giving progress visibility.
          - `get_workflow_step` reports each sub-step's id; edit one with
            `update_sub_step` (name, instructions, position, required), drop one with
            `delete_sub_step`, and fix the order with `reorder_sub_steps` (which
            takes every sub-step id of the step).

          Prefer `get_workflow` to inspect the current shape and `get_workflow_step`
          to read a step in full before editing, and make one focused change per
          tool call.
        GUIDE
      end

      private

      def section(title, blurb, definitions)
        return nil if definitions.empty?

        lines = definitions.sort_by(&:name).map { |d| "- `#{d.name}` — #{summary(d.description)}" }
        [ "## #{title}", blurb, lines.join("\n") ].compact.join("\n") + "\n"
      end

      # First sentence only: this is a map, and the full text of all ~85
      # descriptions is already on the wire in `tools/list`.
      def summary(description)
        first = description.to_s.split(/(?<=[.!?])\s+/).first.to_s.strip
        return first if first.length <= 200

        "#{first[0, 200].sub(/\s+\S*\z/, '')}…"
      end
    end
  end
end
