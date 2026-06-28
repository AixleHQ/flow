# Tools

A **Tool** is a callable an agent can invoke during a session. Tools are
delivered to the runtime over MCP (see the MCP servers page), but the
definition of *what a tool is, who owns it, and where it runs* lives in
the platform.

## Kinds

| Kind       | Owned by      | Visible in UI | How it's attached                                     |
| ---------- | ------------- | ------------- | ----------------------------------------------------- |
| `custom`   | Company / Project | Yes       | Created by users; attached explicitly to workflows/steps. |
| `system`   | Platform      | Yes           | Platform-provided "big" tools; attached explicitly.   |
| `internal` | Platform      | No            | Auto-injected when a session has container tools (e.g. `read_tool_result`). |
| `workflow` | Platform      | No            | Auto-injected only in workflow-step sessions (`list_sub_steps`, `mark_sub_step`). |

`custom` and `system` tools are the ones you manage in the UI. `internal`
and `workflow` tools are invisible plumbing the platform adds for you.

## Execution modes

Every tool runs in one of two places:

| Mode        | Runs in                                  | Characteristics        |
| ----------- | ---------------------------------------- | ---------------------- |
| `app`       | the Rails process (`InternalToolExecutor`) | synchronous, fast.   |
| `container` | a Docker container via Temporal          | asynchronous, isolated, long-running (up to 1 hour). |

Board manipulation and session lifecycle run in `app` mode. A custom
tool that needs its own dependencies runs in `container` mode and must
declare a `docker_image`.

## Built-in tools

The platform seeds a set of tools (see `db/seeds/platform_tools.rb`).
The most visible group are the **board tools**, exposed through the
internal `aixle-tools` MCP server:

| Tool                  | Purpose                                                       |
| --------------------- | ------------------------------------------------------------- |
| `board_get_board_info` | Return the current board with its columns.                   |
| `board_list_tasks`     | List tasks, filtered by column / tag / type / assignee.      |
| `board_get_task`       | Full details for a task (defaults to the bound task).         |
| `board_create_task`    | Create a task, optionally in a specific column.               |
| `board_update_task`    | Update title, description, priority, tags, or type.           |
| `board_move_task`      | Move a task to another column by name.                        |
| `board_add_comment` / `board_get_comments` | Add or read agent comments (Markdown). |
| `board_attach_asset` / `board_get_task_assets` | Attach or list task files.        |
| `board_manage_tags`    | Add or remove a tag on a task or comment.                     |
| `board_create_gate`    | Create a Gate so a column's auto-workflow won't fire until it resolves (e.g. `github_checks_completed`). |

Plus the always-present lifecycle and progress tools: `finish_session`,
`fail_session`, `list_sub_steps`, `mark_sub_step`, `read_tool_result`.

## Custom tools

Create custom tools under **Company → Tools** or **Project → Tools**. A
custom tool requires a `docker_image` and a unique, snake_case `name`
within its scope. It runs in `container` mode and can do whatever its
image can do — the platform passes it parameters and captures its output
as a tool result the agent can read back with `read_tool_result`.

## Resource resolution

For each step, the effective set of tools (and skills, MCP servers,
repositories) is computed by **adding** three layers — there is no
subtraction layer, so build narrowly and add up:

1. Workflow base resources (`workflow.config.base_*_ids`).
2. Step-specific resources (`step.*_ids`).
3. Project-level resources, if `inherit_all_project_resources: true`.

Duplicates are deduplicated by ID. Platform `system`/`internal`/`workflow`
tools are always available where applicable, independent of these layers.

## See also

- **MCP servers** — the transport that delivers tools to the agent.
- **Agents** — how tools fit into the assembled session context.
- **Workflows** — attaching tools to steps.
