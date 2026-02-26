# Story 19.1: Add `execution_mode` to Tool Model

Status: review

## Story

As a system,
I want tools to declare whether they execute in-app or in a container,
so that routing is explicit and not inferred from `kind`.

## Acceptance Criteria

1. Migration adds `execution_mode` string column to `tools` table with default `"container"`
2. `Tool` model gains `enumerize :execution_mode, in: %i[app container], default: :container`
3. `Tool#execute` routes based on `execution_mode`: `:app` → `InternalToolExecutor`, `:container` → `start_container_execution`
4. Old routing logic based on `kind: :internal` removed from `Tool#execute`
5. Existing seeds updated: `list_sub_steps`, `mark_sub_step`, `write_step_note` → `execution_mode: :app`; `code_climate` → `execution_mode: :container`
6. Default `:container` means existing custom tools work without seed changes

## Tasks / Subtasks

- [x] Task 1: Migration (AC: #1)
  - [x] `rails g migration AddExecutionModeToTools execution_mode:string`
  - [x] Default value `"container"`, not null
- [x] Task 2: Model update (AC: #2, #3, #4)
  - [x] Add `enumerize :execution_mode, in: %i[app container], default: :container`
  - [x] Rewrite `Tool#execute` — route by `execution_mode.to_sym` instead of `internal?`
  - [x] Add `tool_result_id` keyword arg to `execute` signature
  - [x] Add private `start_container_execution` and `build_strategy` methods (stubs for now — strategies come in 19.4-19.6)
  - [x] Remove `execute_custom` private method
  - [x] Remove `start_execution` method (replaced by unified `start_container_execution`)
- [x] Task 3: Update seeds (AC: #5)
  - [x] `db/seeds.rb` — update existing internal tool seeds with `execution_mode: :app`
  - [x] `db/seeds/code_report.rb` — ensure code_climate seed has `execution_mode: :container`
- [x] Task 4: Tests (AC: #1-#6)
  - [x] Test routing: app tool → InternalToolExecutor
  - [x] Test routing: container tool → start_container_execution
  - [x] Test default execution_mode for new tools

## Dev Notes

- `kind` (internal/custom) is NOT removed — it still controls scoping and MCP visibility
- `execution_mode` controls HOW the tool runs — orthogonal to `kind`
- `start_container_execution` will initially delegate to existing `ToolExecutionStrategy` for backward compatibility; later stories (19.4-19.5) replace the strategy
- Validation: `custom?` tools must be `execution_mode: :container` (custom app tools make no sense)

### Project Structure Notes

- Migration: `db/migrate/YYYYMMDD_add_execution_mode_to_tools.rb`
- Model: `app/models/tool.rb` — modify existing file
- Seeds: `db/seeds.rb`, `db/seeds/code_report.rb` — modify existing files

### References

- [Source: ai/tool-execution-framework.md#1.1-1.2] — execution_mode definition and routing
- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.1] — acceptance criteria
- [Source: app/models/tool.rb] — current Tool model with `kind` and `execute` method
