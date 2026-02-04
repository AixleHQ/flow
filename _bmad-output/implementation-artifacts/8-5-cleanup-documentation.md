# Story 8.5: Cleanup and Documentation

Status: ready-for-dev

## Story

As a development team,
I want deprecated code removed and new architecture documented,
So that the codebase is clean, maintainable, and the unified container framework is easy to understand and extend.

## Architecture Decision

**Approach:** Remove all deprecated code, update documentation, create migration guide.

**What to Remove:**
- `ToolExecutionService` (replaced by `ToolExecutionStrategy`)
- `ContainerService.start_auth_container` (replaced by `AgentAuthStrategy`)
- `ContainerService.start_agent_container` (replaced by `AgentSessionStrategy`)
- Old workflow implementations if fully migrated

**What to Keep:**
- `ContainerService` helper methods (extract_files, stop_container, health_check)
- Old workflows temporarily for gradual migration (can remove if all callers updated)

## Acceptance Criteria

1. ✅ All deprecated services/methods removed
2. ✅ No references to deprecated code in codebase
3. ✅ Architecture documentation updated
4. ✅ Migration guide created for extending framework
5. ✅ README updated with new patterns
6. ✅ All tests passing after cleanup
7. ✅ Performance comparison documented
8. ✅ Epic 8 marked as complete

## Tasks

### Task 1: Remove Deprecated Code (AC: 1, 2)

- [ ] Delete `app/services/tool_execution_service.rb`
- [ ] Remove deprecated methods from `app/services/container_service.rb`:
  ```ruby
  # Remove:
  # - start_auth_container
  # - start_agent_container
  #
  # Keep:
  # - extract_files (still used by strategies)
  # - stop_container (still used by cleanup activity)
  # - health_check (still used by strategies)
  # - build_traefik_labels (move to helper if needed)
  # - build_tmpfs_mounts (move to helper if needed)
  # - mcp_server_url (move to helper if needed)
  ```
- [ ] Search for references to removed code:
  ```bash
  rg "ToolExecutionService" --type ruby
  rg "start_auth_container" --type ruby
  rg "start_agent_container" --type ruby
  ```
- [ ] Update any remaining references to use new framework
- [ ] Remove old workflow files if fully migrated:
  - `app/temporal/workflows/tool_execution_workflow.rb` (if not used)
  - Keep `agent_session_workflow.rb` and `agent_auth_workflow.rb` if controllers still use them

**Acceptance:** No deprecated code remains, no broken references

---

### Task 2: Extract Helper Methods (AC: 1)

- [ ] Create `app/services/container_helpers.rb`:
  ```ruby
  module ContainerHelpers
    class << self
      # Extract files from running container
      def extract_file_from_container(container, path)
        tar_data = container.copy(path)
        extract_from_tar(tar_data, File.basename(path))
      end

      # Extract from TAR archive
      def extract_from_tar(tar_data, filename)
        require "rubygems/package"

        Tempfile.create(["container-file", ".tar"]) do |temp_file|
          temp_file.binmode
          temp_file.write(tar_data)
          temp_file.rewind

          Gem::Package::TarReader.new(temp_file) do |tar|
            tar.each do |entry|
              if entry.full_name == filename || entry.full_name.end_with?("/#{filename}")
                return entry.read
              end
            end
          end
        end

        nil
      end

      # Build Traefik labels for routing
      def build_traefik_labels(route_token)
        router_name = "terminal-#{route_token}"

        {
          "traefik.enable" => "true",

          # TTY router
          "traefik.http.routers.#{router_name}-tty.rule" => "PathPrefix(`/t/#{route_token}/tty`)",
          "traefik.http.routers.#{router_name}-tty.middlewares" => "terminal-auth,#{router_name}-tty-strip",
          "traefik.http.middlewares.#{router_name}-tty-strip.stripprefix.prefixes" => "/t/#{route_token}/tty",
          "traefik.http.routers.#{router_name}-tty.service" => "#{router_name}-tty",
          "traefik.http.services.#{router_name}-tty.loadbalancer.server.port" => "7681",

          # File watcher router
          "traefik.http.routers.#{router_name}-fs.rule" => "PathPrefix(`/t/#{route_token}/fs`)",
          "traefik.http.routers.#{router_name}-fs.middlewares" => "terminal-cors,terminal-auth,#{router_name}-fs-strip",
          "traefik.http.middlewares.#{router_name}-fs-strip.stripprefix.prefixes" => "/t/#{route_token}/fs",
          "traefik.http.routers.#{router_name}-fs.service" => "#{router_name}-fs",
          "traefik.http.services.#{router_name}-fs.loadbalancer.server.port" => "4040"
        }
      end

      # Build tmpfs mounts
      def build_tmpfs_mounts(paths, uid = 1001)
        paths.each_with_object({}) do |path, hash|
          hash[path] = "rw,size=50m,mode=0755,uid=#{uid},gid=#{uid}"
        end
      end

      # MCP server URL
      def mcp_server_url
        ENV.fetch("MCP_SERVER_URL", "http://web:3000/action_mcp")
      end

      # Traefik base URL
      def traefik_base_url
        Settings.traefik.ws_base
      end
    end
  end
  ```
- [ ] Update strategies to use `ContainerHelpers` instead of `ContainerService`
- [ ] Slim down `ContainerService` to only used methods or remove entirely

**Acceptance:** Helper methods centralized and reusable

---

### Task 3: Update Architecture Documentation (AC: 3)

- [ ] Update `ai/epic-8-unified-container-architecture.md`:
  - Add "Implementation Status: Complete" section
  - Add performance metrics (if available)
  - Add troubleshooting section
  - Add examples of extending framework
- [ ] Create `ai/container-strategies-guide.md`:
  ```markdown
  # Container Strategies Guide

  ## Overview
  Guide for creating new container strategies.

  ## Creating a New Strategy

  1. Inherit from BaseStrategy
  2. Implement required methods
  3. Override lifecycle hooks as needed
  4. Register in ExecuteContainerActivity

  ## Example: Database Migration Strategy

  [Full example implementation]

  ## Testing Your Strategy

  [Testing guide]
  ```

**Acceptance:** Architecture fully documented

---

### Task 4: Create Migration Guide (AC: 4)

- [ ] Create `ai/epic-8-migration-guide.md`:
  ```markdown
  # Epic 8 Migration Guide

  ## For Developers Adding New Container Types

  ### Before Epic 8
  ```ruby
  # Had to modify ContainerService or create new service
  class MyFeatureService
    def self.execute
      # Duplicate Docker logic
    end
  end
  ```

  ### After Epic 8
  ```ruby
  # Create strategy, reuse framework
  class MyFeatureStrategy < ContainerStrategies::BaseStrategy
    def resolve_image
      "my-image:latest"
    end

    def exec(context)
      # Your logic here
    end
  end

  # Use it
  ContainerExecutionService.execute(
    strategy: MyFeatureStrategy.new(...)
  )
  ```

  ## For API/Controller Developers

  ### Starting a Tool Execution

  Before:
  ```ruby
  ToolExecutionService.execute(tool: tool, parameters: params)
  ```

  After:
  ```ruby
  ContainerWorkflowService.start_tool_execution(
    tool: tool,
    parameters: params,
    project: project
  )
  ```

  [More examples...]
  ```

**Acceptance:** Migration guide covers common use cases

---

### Task 5: Update README/Documentation (AC: 5)

- [ ] Update main README.md:
  - Add Epic 8 to "Recent Improvements" section
  - Link to architecture doc
  - Link to strategies guide
- [ ] Update `docs/` folder if exists:
  - Add container execution section
  - Add strategy pattern diagrams
  - Add troubleshooting guide
- [ ] Add inline code comments to:
  - `ContainerExecutionService`
  - `BaseStrategy`
  - Each concrete strategy
  - All activities

**Acceptance:** Documentation complete and up-to-date

---

### Task 6: Performance Testing and Comparison (AC: 7)

- [ ] Create performance benchmark:
  ```ruby
  # test/benchmarks/container_execution_benchmark.rb
  require "benchmark"

  class ContainerExecutionBenchmark
    def self.run
      puts "Epic 8 Container Execution Performance"
      puts "=" * 50

      Benchmark.bm(30) do |x|
        x.report("Tool execution (cached image):") do
          # Measure tool execution with cached image
        end

        x.report("Tool execution (pull image):") do
          # Measure tool execution with image pull
        end

        x.report("Agent session start:") do
          # Measure agent session start
        end
      end
    end
  end
  ```
- [ ] Document results in `ai/epic-8-performance.md`:
  ```markdown
  # Epic 8 Performance Results

  ## Metrics

  | Operation | Before Epic 8 | After Epic 8 | Change |
  |-----------|---------------|--------------|--------|
  | Tool execution (cached) | ~5s | ~5s | No change |
  | Tool execution (pull) | N/A* | ~15s | New feature |
  | Agent session start | ~8s | ~8s | No change |
  | Code complexity | High | Low | 40% reduction |

  *Before: image pull was inline, no separate measurement

  ## Code Metrics

  - Lines of code: 800 → 500 (-37%)
  - Cyclomatic complexity: 45 → 28 (-38%)
  - Test coverage: 75% → 92% (+17%)

  ## Benefits

  1. **Maintainability**: Single execution path for all container types
  2. **Extensibility**: New container type = 50 lines of strategy code
  3. **Testing**: Each strategy tested independently
  4. **Reliability**: Per-phase timeouts prevent hangs
  ```

**Acceptance:** Performance documented, no regressions

---

### Task 7: Final Testing (AC: 6)

- [ ] Run full test suite:
  ```bash
  bundle exec rails test
  ```
- [ ] Run integration tests:
  ```bash
  bundle exec rails test:integration
  ```
- [ ] Manual testing:
  - Start agent auth container
  - Complete authentication
  - Start agent session
  - Execute custom tool
  - Verify artifacts collected
  - Verify cleanup works
- [ ] Load testing (if applicable):
  - Multiple concurrent tool executions
  - Multiple concurrent agent sessions
  - Resource limits enforced

**Acceptance:** All tests pass, system stable

---

### Task 8: Update Sprint Status (AC: 8)

- [ ] Update `ai/sprint-status.yaml`:
  ```yaml
  epics:
    - id: epic-8
      name: "Unified Container Execution Framework"
      status: completed
      completion_date: 2026-02-XX
      stories:
        - id: 8-1
          name: "Container Execution Foundation"
          status: completed
        - id: 8-2
          name: "Tool Execution Strategy"
          status: completed
        - id: 8-3
          name: "Agent Container Strategies"
          status: completed
        - id: 8-4
          name: "Unified Container Workflow"
          status: completed
        - id: 8-5
          name: "Cleanup and Documentation"
          status: completed
  ```
- [ ] Create Epic 8 summary in `ai/epic-8-summary.md`:
  ```markdown
  # Epic 8: Unified Container Execution Framework

  ## Summary
  Successfully unified all container execution logic into a single framework
  using Strategy Pattern with lifecycle hooks.

  ## Completed Stories
  - 8.1: Foundation (ContainerExecutionService, BaseStrategy)
  - 8.2: Tool Migration (ToolExecutionStrategy)
  - 8.3: Agent Migration (AgentAuthStrategy, AgentSessionStrategy)
  - 8.4: Workflow Unification (UnifiedContainerWorkflow)
  - 8.5: Cleanup (removed deprecated code, documentation)

  ## Key Achievements
  - 37% code reduction
  - Per-phase timeout protection
  - Artifact collection standardized
  - Easy to extend (new strategy = 50 lines)

  ## Future Extensions
  - Database migration containers
  - ML training containers
  - Data processing pipelines
  ```

**Acceptance:** Sprint status updated, Epic 8 complete

---

## Implementation Notes

### Breaking Changes

None - all changes are internal. Public APIs remain backward compatible.

### Deprecation Timeline

1. Story 8.1-8.4: Mark code as deprecated
2. Story 8.5: Remove deprecated code
3. No user-facing changes

### Rollback Plan

If issues discovered:
1. Keep old service files in git history
2. Can revert individual strategies
3. Old workflows still work (kept as backup)

---

## File List

### Deleted Files
- `app/services/tool_execution_service.rb`
- `app/services/container_service.rb` (or keep minimal version)
- `test/services/tool_execution_service_test.rb`
- Potentially: old workflow files if fully migrated

### New Files
- `app/services/container_helpers.rb`
- `ai/container-strategies-guide.md`
- `ai/epic-8-migration-guide.md`
- `ai/epic-8-performance.md`
- `ai/epic-8-summary.md`
- `test/benchmarks/container_execution_benchmark.rb`

### Modified Files
- `ai/epic-8-unified-container-architecture.md` (add completion status)
- `ai/sprint-status.yaml` (mark Epic 8 complete)
- `README.md` (add Epic 8 to recent improvements)
- All strategy files (add comprehensive comments)
- All activity files (add comprehensive comments)

---

## Dependencies

- Stories 8.1, 8.2, 8.3, 8.4 all completed
- All tests passing before cleanup
- No pending PRs affecting container code

---

## Success Criteria

- [ ] Zero deprecated code warnings in logs
- [ ] All tests passing
- [ ] Documentation complete
- [ ] Performance metrics documented
- [ ] Epic 8 marked complete in sprint status
- [ ] Team reviewed and approved changes

---

## Dev Agent Record

**Agent Model:** (to be filled during implementation)

**Completion Notes:** (to be filled during implementation)
