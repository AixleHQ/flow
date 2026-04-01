# Story 19.6: InternalToolStrategy with DSL

Status: ready-for-dev

## Story

As a developer,
I want to define internal container tools declaratively via DSL blocks,
so that adding a new tool is ~15 lines instead of ~200.

## Acceptance Criteria

1. `ContainerStrategies::InternalToolStrategy < ToolStrategy` created
2. `Definition` inner class with DSL methods: `image`, `timeout`, `memory`, `cpu_quota`, `working_dir`, `docker_socket!`, `output_files`, `cmd(&block)`, `env(&block)`, `binds(&block)`, `prepare(&block)`
3. Class-level `registry`: `InternalToolStrategy.define(:name) { ... }` registers a Definition
4. `InternalToolStrategy.build_for(name, params:, session:, tool_result_id:)` resolves definition, runs prepare block, returns configured strategy instance
5. `prepare` block executes before container creation (Ruby code, not in container)
6. `before_cleanup` phase collects `output_files` from container → packs tar.gz → attaches to ToolResult
7. Security is per-definition: `docker_socket!` enables docker.sock mount, `binds` block can mount host paths
8. DSL uses `tap` pattern for chainable setters

## Tasks / Subtasks

- [ ] Task 1: Definition class (AC: #2, #8)
  - [ ] `Definition.new(name)` with default opts hash
  - [ ] Scalar DSL methods (image, timeout, memory, cpu_quota, working_dir)
  - [ ] `docker_socket!` flag method
  - [ ] `output_files(v)` array setter
  - [ ] Block DSL methods (cmd, env, binds, prepare)
  - [ ] All methods return `tap { ... }` for chaining
- [ ] Task 2: Registry + build_for (AC: #3, #4, #5)
  - [ ] `self.registry` — class-level hash
  - [ ] `self.define(name, &block)` — create Definition, instance_eval, store
  - [ ] `self.build_for(name, ...)` — find definition, run_prepare, instantiate
  - [ ] `run_prepare` — call prepare block with merged params+session
  - [ ] Raise ArgumentError if definition not found
- [ ] Task 3: Strategy overrides (AC: #1, #6, #7)
  - [ ] `resolve_image` → `defn.opts[:image]`
  - [ ] `build_working_dir` → `defn.opts[:working_dir]`
  - [ ] `build_cmd` → resolve_callable on cmd block
  - [ ] `build_env_vars` → resolve_callable on env block → format as `K=V` array
  - [ ] `build_labels` → `aixle.type: internal_tool, aixle.tool: name`
  - [ ] `build_host_config` → memory/cpu from opts, conditional docker socket + binds
  - [ ] `before_cleanup` → collect output_files, pack, attach to ToolResult
  - [ ] Private `resolve_callable(val)` — Proc → call(input), else return as-is
- [ ] Task 4: Tests
  - [ ] Test define registers a Definition in registry
  - [ ] Test build_for raises for unknown name
  - [ ] Test build_for runs prepare block and merges results
  - [ ] Test resolve_image from definition
  - [ ] Test build_cmd with callable block
  - [ ] Test build_host_config with docker_socket!
  - [ ] Test build_host_config without docker_socket
  - [ ] Test before_cleanup collects output_files and attaches to ToolResult

## Dev Notes

- Tool definitions themselves will be added in Story 19.7 (Code Climate) and potentially later stories
- The `input` hash for InternalToolStrategy includes: definition, tool_result_id, timeout, plus everything from `prepare` block result
- `before_cleanup` runs AFTER `exec` but BEFORE container removal — container filesystem is still accessible

### Project Structure Notes

- `app/services/container_strategies/internal_tool_strategy.rb` — new file

### References

- [Source: ai/tool-execution-framework.md#2.3] — InternalToolStrategy full code
- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.6] — acceptance criteria
