# Tools

A **Tool** is a callable an agent can invoke during a session. Tools are
delivered to the runtime over MCP (see the MCP servers page); this page
covers what a tool is, who owns it, where it runs, and how it ends up
available to an agent.

## Platform tools vs custom tools

Every tool is one of two things:

| | Platform tool | Custom tool |
| --- | --- | --- |
| Owned by | Aixle (built in) | you (Company / Project) |
| Created | ships with the platform | in the UI, by the Aixle Builder, or over the personal MCP |
| Runs in | the Aixle process (fast) or a container | a Docker container you specify |
| Managed where | nothing to manage — always current | **Project → Tools** (and **Company → Tools**) |

The rule of thumb: **platform behaviour comes built in; custom tools are
your own code in a container.** You never seed or register a platform
tool — it is always there and always up to date.

## Where a tool runs

| Mode | Runs in | Characteristics |
| --- | --- | --- |
| In-process | the Aixle process | synchronous, fast (board edits, workflow control, session lifecycle) |
| Container | a Docker container via Temporal | asynchronous, isolated, long-running (up to 1 hour) |

A container tool returns an execution id immediately; the container runs in
the background and the agent reads the result back with `read_tool_result`.

## Built-in tools

The most visible built-ins are the **board tools**, plus workflow-control
and lifecycle tools:

| Tool | Purpose |
| --- | --- |
| `board_get_board_info` | Return the current board with its columns. |
| `board_list_tasks` | List a page of tasks (no descriptions), filtered by column / tag / type / assignee. |
| `board_get_task` | Full details for a task. |
| `board_create_task` | Create a task, optionally in a specific column. |
| `board_update_task` | Update title, description, priority, tags, or type. |
| `board_move_task` | Move a task to another column. |
| `board_add_comment` / `board_get_comments` | Add or read comments (Markdown). |
| `board_attach_asset` / `board_get_task_assets` | Attach or list task files. |
| `board_manage_tags` | Add or remove a tag on a task or comment. |
| `board_create_gate` | Hold a column's auto-workflow until a gate resolves. |
| `list_sub_steps` / `mark_sub_step` | Track progress within a step. |
| `finish_session` / `fail_session` | Signal a non-interactive session done or failed. |
| `read_tool_result` | Fetch the result of an async container tool. |

## Custom tools

Create custom tools under **Project → Tools** (or **Company → Tools**). A
custom tool needs a Docker image and a unique, lowercase `name` within its
scope. It runs in a container, receives your parameters, and its output
becomes a tool result the agent reads back with `read_tool_result`.

Because a custom tool's name, description and schema are shown to the agent
alongside built-in tools, Aixle validates them on save: the name can't
collide with a built-in tool or use the reserved `mcp__` namespace, the
input schema must be valid, and the image is pinned so a moving tag can't
swap the code out from under you.

## How tools become available

You rarely attach every tool by hand. For a given session Aixle assembles:

1. **What you attached** — the tools you picked on a workflow step (or added
   to a session). *Manual.*
2. **Your project's custom tools** — pulled in automatically when a session
   has a project and you didn't attach custom tools yourself. *Automatic.*
3. **Built-ins the context needs** — *automatic*:
   - board and workflow-control tools when a workflow step runs;
   - `read_tool_result` when a container tool is present;
   - `finish_session` / `fail_session` in non-interactive runs.

So workflow mechanics attach themselves — a workflow started from a board
task already has the board tools. You attach **by hand** when you want a
tool the rules don't add: for example, giving the board tools to a workflow
that did *not* start from a board task, or adding a specific custom tool to
one step.

### Integration gating

A tool that needs an integration only appears once that integration is
connected: `slack_post_message` is hidden until Slack is connected for the
project; the Coder tools appear only with an active Coder integration. If an
agent calls a tool whose integration isn't connected, it gets a clear
message telling it (and you) to connect it in **Project Settings →
Integrations** — nothing is silently dropped.

## Tool groups in the picker

In the workflow builder, related tools are offered as a single group instead
of a long flat list. Selecting **Board management** attaches every board tool
at once — you don't tick each one. Custom tools and ungrouped tools are still
listed individually. Grouping is presentation only; the step still stores the
individual tools.

## Personal MCP

You can also connect your own AI agent (Claude Code, Cursor, …) to Aixle
directly, without a session, using a personal token from your profile — it
gets exactly your access level. See the MCP servers page.

## See also

- **MCP servers** — the transport that delivers tools, and the personal token.
- **Workflows** — attaching tools to steps.
- **Integrations** — connecting Slack, Coder, GitHub and more.
