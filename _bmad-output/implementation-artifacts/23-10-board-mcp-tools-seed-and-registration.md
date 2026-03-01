# Story 23.10: Board MCP Tools Seed & Registration

Status: ready-for-dev

## Story

As a developer,
I want all 13 board MCP tools seeded and registered,
so that they're available in workflow sessions after deploy.

## Acceptance Criteria

1. Seeds create 13 `Tool` records with `kind: :workflow`, `execution_mode: :app`, `enabled: true`
2. 5 read tools: `board_list_tasks`, `board_get_task`, `board_get_comments`, `board_get_task_assets`, `board_get_board_info`
3. 6 write tools: `board_create_task`, `board_update_task`, `board_move_task`, `board_add_comment`, `board_attach_asset`, `board_manage_tags`
4. 2 diagnostic tools: `board_fail_session`, `board_request_human_help`
5. All tools: `scope: nil` (platform tools, no company/project scope)
6. Each tool has proper `input_schema` (JSON Schema) and `description`
7. Tool names prefixed with `board_` for namespace isolation
8. Seeds are idempotent: `find_or_initialize_by(name: ..., kind: :workflow)`
9. Running `rails db:seed` does not create duplicates

## Tasks / Subtasks

- [ ] Task 1: Add 5 read tool seed definitions to `db/seeds.rb`
- [ ] Task 2: Add 6 write tool seed definitions to `db/seeds.rb`
- [ ] Task 3: Add 2 diagnostic tool seed definitions to `db/seeds.rb`
- [ ] Task 4: Run seeds and verify 13 tools are created
- [ ] Task 5: Verify tools appear in workflow_step session's `available_tools`

## Dev Notes

### Architecture Compliance

- **kind: :workflow** — auto-injected into `workflow_step` sessions via `TerminalSession#available_tools`
- **execution_mode: :app** — executed by `InternalToolExecutor` in Rails process
- **scope: nil** — platform-level tools, not scoped to company or project
- **name normalization**: Tool model downcases and replaces non-alphanumeric with `_`
- **Idempotent**: `find_or_initialize_by` pattern from existing seeds

### Seed Pattern (Following Existing)

```ruby
# Board MCP Read Tools
Tool.find_or_initialize_by(name: "board_list_tasks", kind: :workflow).update!(
  display_name: "List Board Tasks",
  description: "List tasks on the board with optional filters. Auto-resolves board from session context.",
  input_schema: {
    type: "object",
    properties: {
      column_name: { type: "string", description: "Filter by column name" },
      tag: { type: "string", description: "Filter by tag" },
      task_type: { type: "string", enum: %w[epic story bug not_specified], description: "Filter by task type" },
      assignee_id: { type: "integer", description: "Filter by assignee user ID" }
    }
  },
  execution_mode: :app,
  enabled: true
)
```

### Full Tool List with Input Schemas

**Read tools:**

| Tool Name | Required Params | Optional Params |
|-----------|----------------|-----------------|
| `board_list_tasks` | — | `column_name`, `tag`, `task_type`, `assignee_id` |
| `board_get_task` | `task_id` | — |
| `board_get_comments` | `task_id` | `tag`, `author_type` |
| `board_get_task_assets` | `task_id` | `tag` |
| `board_get_board_info` | — | — |

**Write tools:**

| Tool Name | Required Params | Optional Params |
|-----------|----------------|-----------------|
| `board_create_task` | `title` | `description`, `task_type`, `column_name`, `tags` |
| `board_update_task` | `task_id` | `title`, `description`, `priority`, `tags`, `task_type` |
| `board_move_task` | `task_id`, `column_name` | — |
| `board_add_comment` | `task_id`, `body` | `tags` |
| `board_attach_asset` | `task_id`, `file_content`, `name` | `tags` |
| `board_manage_tags` | `action`, `entity_type`, `entity_id`, `tag` | — |

**Diagnostic tools:**

| Tool Name | Required Params | Optional Params |
|-----------|----------------|-----------------|
| `board_fail_session` | `reason` | — |
| `board_request_human_help` | `question` | — |

### Tool Descriptions (Agent-Facing)

Each description should explain what the tool does and key constraints:
- `board_list_tasks`: "List tasks on the board. Filters: column_name, tag, task_type, assignee_id. Board resolved automatically from session context."
- `board_get_board_info`: "Get board structure including columns with names, purposes, and workflow bindings. Use this to understand the current board layout and what each column expects."
- `board_add_comment`: "Add a comment to a task. author_type is automatically set to 'agent'. Use tags like 'tech_design', 'code_review', 'feedback' to categorize."
- `board_fail_session`: "Terminate the current workflow session with an error reason. Use when the task cannot be completed. Session will be marked as failed."
- `board_request_human_help`: "Pause the session and request human input. Provide a clear question. The session will resume after human responds."

### Verification

After seeding, verify:
```ruby
Tool.workflow_tools.where("name LIKE 'board_%'").count # => 13
Tool.workflow_tools.where("name LIKE 'board_%'").pluck(:name).sort
# => ["board_add_comment", "board_attach_asset", "board_create_task", "board_fail_session",
#     "board_get_board_info", "board_get_comments", "board_get_task", "board_get_task_assets",
#     "board_list_tasks", "board_manage_tags", "board_move_task", "board_request_human_help",
#     "board_update_task"]
```

### Dependency

- Requires Story 23.6, 23.7, 23.8 (tool implementations) — but seeds can be created beforehand
- Tool implementations must match the names exactly (`board_list_tasks` → `InternalTools::BoardListTasks`)

### Project Structure Notes

- `db/seeds.rb` (modified: add 13 board tool definitions)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.10]
- [Source: db/seeds.rb — existing workflow tool seed pattern]
- [Source: app/models/tool.rb — kind: :workflow, scope: nil for platform tools]
- [Source: app/models/terminal_session.rb#available_tools — workflow tool injection]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
