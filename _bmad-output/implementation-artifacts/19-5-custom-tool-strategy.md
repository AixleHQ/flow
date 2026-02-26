# Story 19.5: CustomToolStrategy

Status: ready-for-dev

## Story

As a developer,
I want custom tool execution refactored into a ToolStrategy subclass,
so that it shares lifecycle logic with internal tools and persists results to ToolResult.

## Acceptance Criteria

1. `ContainerStrategies::CustomToolStrategy < ToolStrategy` created
2. `resolve_image` → `input[:tool].docker_image`
3. `build_cmd` → interpolated command with tool_files support
4. `build_env_vars` → parameters as ENV + config_items + project env
5. `build_host_config` → Settings-based resource limits, no bind mounts, no docker socket
6. `build_labels` → palad labels with tool_id and tool_name
7. Output: stdout/stderr only — no file collection from container
8. All existing custom tool functionality preserved (command interpolation, tool_files setup, config_item resolution)
9. Old `ToolExecutionStrategy` functionality fully covered

## Tasks / Subtasks

- [ ] Task 1: CustomToolStrategy class (AC: #1-#7)
  - [ ] Create `app/services/container_strategies/custom_tool_strategy.rb`
  - [ ] Inherit from `ToolStrategy`
  - [ ] `before_create_container` validation: tool must have docker_image
  - [ ] `resolve_image` — from Tool model
  - [ ] `build_working_dir` — `/workspace`
  - [ ] `build_cmd` — interpolate_command + tool_files setup
  - [ ] `build_env_vars` — parameters → ENV vars + config_items + project env
  - [ ] `build_labels` — palad metadata labels
  - [ ] `build_host_config` — delegate to `build_host_config_with_limits`
- [ ] Task 2: Move private helpers (AC: #8)
  - [ ] `interpolate_command(template, params)` — from `ToolExecutionStrategy`
  - [ ] `file_setup_cmd(tool_file)` — from `ToolExecutionStrategy`
  - [ ] `resolve_config_items` — from `ToolExecutionStrategy`
  - [ ] `inject_project_env(env_hash)` — from `ToolExecutionStrategy`
- [ ] Task 3: Tests (AC: #1-#9)
  - [ ] Test image resolution from tool model
  - [ ] Test command interpolation with parameters
  - [ ] Test command with tool_files generates setup commands
  - [ ] Test env vars include parameters + config items
  - [ ] Test host_config has no bind mounts
  - [ ] Test host_config has no docker socket
  - [ ] Test labels contain tool metadata

## Dev Notes

- Zero behavior change for custom tools — only the result storage path changes (ToolResult → Shrine instead of Temporal payload)
- Private helpers are copied verbatim from `ToolExecutionStrategy`, no logic changes
- `ToolExecutionStrategy` is NOT deleted in this story — deletion is Story 19.13 after all migrations are verified

### Project Structure Notes

- `app/services/container_strategies/custom_tool_strategy.rb` — new file

### References

- [Source: ai/tool-execution-framework.md#2.2] — CustomToolStrategy design
- [Source: app/services/container_strategies/tool_execution_strategy.rb] — source of migrated logic
