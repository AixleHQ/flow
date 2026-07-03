# Tools

How Aixle tools are defined, discovered, served over MCP, and attached to
sessions and workflow steps.

## Two kinds of tool

| | Platform tool | Custom tool |
|---|---|---|
| Authored by | us, in code | a user, in the UI / `meta_create_tool` / personal MCP |
| Lives in | an `InternalTools::*` (or `PersonalTools::*`) Ruby class | a `tools` row (`source: "db"`) |
| Runs | in the Rails process (`execution_mode: app`) or a Docker container | a Docker container (`docker_image` + `command`) |
| DB row | a reconciler-owned **shadow row** (`source: "code"`), or none for personal tools | the authored row itself |

The rule of thumb: **platform behaviour is code, user data is a row.** Adding
a platform tool is writing a class — no seed, no migration.

## Defining a platform tool

A platform tool is a handler class with a `tool do ... end` block. Writing the
class *is* the registration.

```ruby
# app/services/internal_tools/slack_post_message.rb
module InternalTools
  class SlackPostMessage < Base
    tool do
      display_name "Slack Post Message"
      description  "Send a Slack message from this workflow..."
      tags         :messaging, :slack        # grouping / provider marker (see Tags)
      inject_when  :workflow_step_session     # auto-attach rule (see Attachment)
      requires_integration :slack             # availability gate (see Availability)
      read_only false                         # MCP behavior annotation
      param :text,    type: :string, description: "Message text."
      param :channel, type: :string, description: "Channel id."
      # input_schema(raw_hash) is the escape hatch for complex JSON Schemas
    end

    def execute
      # returns { exit_code:, stdout:, stderr: }
    end
  end
end
```

The DSL (`Tools::DefinitionDSL`) supports: `display_name`, `description`,
`tags`, `inject_when`, `requires_integration`, `availability` (a custom
lambda), `user_attachable`, `managed_mcp_provider`, MCP annotations
(`read_only` / `destructive` / `idempotent` / `open_world`), `audience`, and
either `param` sugar or a raw `input_schema`.

### Registry, definitions, shadow rows

- **`Tools::Registry`** discovers every `InternalTools::Base` /
  `PersonalTools::Base` descendant that declares a `tool` block
  (`eager_load_namespace` + `descendants`, memoized as frozen
  `Tools::Definition` POROs, reset on code reload). It never caches class
  objects — the definition holds the class *name* and constantizes at call
  time.
- **`Tools::Reconciler`** projects `audience: :session` definitions into
  `tools` shadow rows (`source: "code"`) so existing FKs
  (`tool_results.tool_id`, `session_tools`, workflow-step `tool_ids`) keep
  working. It is diff-based (steady-state runs write nothing), advisory-lock
  guarded, and runs on deploy (`rails platform_tools:seed`), at boot
  (self-heal), and lazily via `Tool.shadow_for` on first FK need. Removed
  definitions are soft-deleted, never destroyed.
- The definition — not the row — is authoritative for serving: a stale row
  between deploy and reconcile can never serve a stale schema.
- **`rails tools:check`** reports drift (missing/orphan rows, definition
  mismatch, custom-name collisions); exit code 2 = drift.

Adding / changing a platform tool: edit the class. **Renaming** still needs a
data migration (to keep the shadow row's id and history) — the reconciler
alone would soft-delete the old row and insert a new one, orphaning
`steps.tool_ids`.

## Custom (user) tools

A custom tool is a `tools` row (`source: "db"`, a `docker_image`, an optional
`command` template with `{{param}}` placeholders, an `input_schema`, and
`tool_files`), scoped to a Company or Project. Created through the UI,
`meta_create_tool`, or the personal MCP `create_custom_tool`.

Because custom definitions (name, description, schema) are user-authored and
share one `tools/list` with platform tools, they go through a hardening
pipeline in the model:

- **name** cannot collide with a platform tool name or use the reserved
  `mcp__` namespace (validation + a DB `CHECK`);
- **input_schema** is meta-validated (JSON Schema 2020-12), the `$ref` family
  is rejected, and size/depth are capped;
- free text (description + nested schema descriptions) is screened for
  instruction-injection markers;
- a **`definition_digest`** is stamped on every validated save. Serving
  re-verifies it and **fails closed** — a row written past validations
  (`update_columns`, raw SQL) vanishes from `tools/list` instead of serving
  tampered metadata;
- the **`docker_image` is digest-pinned** at first execution, so a mutable
  tag can't swap the code later.

Execution: a container tool call returns an `execution_id` immediately; the
container runs in a Temporal workflow; the agent polls `read_tool_result`.

## How tools are served over MCP

One endpoint (`/mcp`, alias `/action_mcp`), two principals split by credential:

- **Session key** (`X-Session-Key` = a `TerminalSession#mcp_key`) →
  `Tools::MCPRequestHandler` serves the session's entitled `audience: :session`
  tools.
- **Personal token** (`amcp_...` bearer) → `Tools::PersonalMCPRequestHandler`
  serves `audience: :user` tools with the user's own access level. See
  [Personal MCP](#personal-mcp).

Both build a stateless `MCP::Server` per request (official `mcp` gem), sort
deterministically, put tags in `_meta`, and serialize registry-first.

## Attachment: what's automatic vs manual

For a **session**, `TerminalSession#available_tools` assembles:

1. **Explicitly attached** tools (`session_tools`, or a workflow step's
   `tool_ids`) — *manual*: you pick these in the workflow builder / picker.
2. **Project custom-tool fallback** — if nothing custom is attached and the
   session has a project, its custom tools come along — *automatic*.
3. **Injected platform tools** — *automatic*, by `inject_when` rule:
   - `workflow_step_session` → board tools, `list_sub_steps`, `mark_sub_step`,
     `slack_post_message` inject into `workflow_step` sessions;
   - `container_tools_present` → `read_tool_result` injects when the session
     has any container tool;
   - `non_interactive_session` → `finish_session` / `fail_session` inject in
     non-interactive mode.

So: **workflow / session mechanics attach themselves** (a workflow started
from a board task already has the board tools; an async session already has
`read_tool_result`). You attach **manually** when you want a tool the rules
don't add — e.g. granting board tools to a session that did *not* start from a
board task, or adding a custom tool to a specific step.

### Availability gating

`Tool#available?(context)` runs on every `tools/list` (hide) and `tools/call`
(enforce), from one batched integration query:

- `requires_integration :slack` hides the tool until an active Slack
  integration exists for the project;
- calling an entitled-but-disconnected tool returns an actionable in-band
  error ("Slack is not connected — connect it in Project Settings");
- calling a tool outside your entitlement returns an opaque
  `method_not_found`, so remedy text can't leak capability existence;
- coder / managed tools surface only through their managed MCP server, under
  the `mcp__<server>__<tool>` namespace.

## Tags and picker groups

Tags are the grouping axis, governed by **`Tools::TagCatalog`** — the single
source of truth for label / UI visibility / presentation:

| Tag | Label | In picker | Presentation |
|---|---|---|---|
| `board` | Board management | yes | **group** (one selectable entry) |
| `messaging` | Messaging | yes | individual |
| `slack` | Slack | no | provider marker |
| `coder` | Coder | no | managed server |
| `workflow_control`, `async_results`, `session_lifecycle`, `builder` | — | no | auto-inject / builder-only |

A `:group` tag (currently `board`) shows in the workflow builder tool picker
as **one entry** that stands in for all its tools — selecting "Board
management" attaches every board tool at once; the members are not listed
individually (all-or-nothing). Ungrouped and custom tools stay individual.
`Tools::PickerGroups.for_project` resolves a group to that project's tool ids;
the builder expands the group token on save.

To change grouping: edit `ENTRIES` in `app/services/tools/tag_catalog.rb`.

## Personal MCP

Each user can enable a personal token (profile page) that connects their own
agent to a **session-less** MCP server granting exactly their access level —
every tool authorizes through the same Pundit policies the UI uses. Personal
tools (`audience: :user`, in `app/services/personal_tools/`) cover companies,
projects, board, workflows (build + run), agents, custom tools, skills, MCP
servers, config items, repositories, assets and project settings. They are
never materialized as shadow rows, never injected into sessions, and never
appear in the session picker. Two MCP prompts — `build_workflow` and
`author_step` — guide the multi-step flows.

## Where things live

| Concern | Path |
|---|---|
| Platform tool handlers | `app/services/internal_tools/` |
| Personal tool handlers | `app/services/personal_tools/` |
| DSL / Definition / Registry / Reconciler / Context | `app/services/tools/` |
| Tag catalog + picker groups | `app/services/tools/tag_catalog.rb`, `picker_groups.rb` |
| MCP endpoint | `app/controllers/mcp_controller.rb` + `Tools::*MCPRequestHandler` |
| Custom-tool execution | `app/services/container_strategies/custom_tool_strategy.rb` |
| Drift check | `rails tools:check` |
