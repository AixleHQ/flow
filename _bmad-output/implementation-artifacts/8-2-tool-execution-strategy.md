# Story 8.2: Tool Execution Strategy Migration

Status: ready-for-dev

## Story

As a system,
I want to migrate tool execution to use the unified container framework,
So that tools benefit from standardized lifecycle hooks, timeouts, and artifact collection.

## Architecture Decision

**Approach:** Implement `ToolExecutionStrategy` inheriting from `BaseStrategy`, migrate existing `ToolExecutionService` logic.

**Key Changes:**
- Move tool-specific logic from `ToolExecutionService` → `ToolExecutionStrategy`
- Leverage lifecycle hooks for file injection, execution, cleanup
- Add artifact collection in `before_cleanup` phase
- Keep `ExecuteToolActivity` but simplify to use new service

```
Before:
ExecuteToolActivity → ToolExecutionService (monolithic)

After:
ExecuteToolActivity → ContainerExecutionService.execute(
  strategy: ToolExecutionStrategy.new(tool:, parameters:, project:)
)
```

## Acceptance Criteria

1. ✅ `ToolExecutionStrategy` implements all lifecycle phases
2. ✅ Config item resolution works (API keys, env vars)
3. ✅ File injection in `before_exec` phase
4. ✅ Command execution with timeout enforcement (5-30 min)
5. ✅ Output truncation (1MB limit) to prevent memory issues
6. ✅ Artifact collection from tool output paths
7. ✅ Resource limits enforced (CPU 50%, Memory 512MB)
8. ✅ Backward compatibility: existing tool executions work
9. ✅ Tests updated and passing

## Tasks

### Task 1: Create ToolExecutionStrategy (AC: 1, 2)

- [ ] Create `app/services/container_strategies/tool_execution_strategy.rb`
- [ ] Inherit from `BaseStrategy`
- [ ] Implement `resolve_image`:
  ```ruby
  def resolve_image
    input[:tool].docker_image
  end
  ```
- [ ] Implement `build_env_vars` with config item resolution:
  ```ruby
  def build_env_vars
    env_hash = resolve_config_items(input[:tool], input[:project])
    env_hash.map { |k, v| "#{k}=#{v}" }
  end

  private

  def resolve_config_items(tool, project)
    return {} if tool.required_config_items.blank?

    env_vars = {}
    company = project&.company || tool.scope

    tool.required_config_items.each do |name|
      config_item = find_config_item(name, project, company)
      next unless config_item

      env_name = name.upcase.gsub(/[^A-Z0-9_]/, "_")
      env_vars[env_name] = config_item.decrypted_value
    end

    env_vars
  end
  ```
- [ ] Add `WorkingDir: /workspace` to container config

**Acceptance:** Strategy resolves image and config items correctly

---

### Task 2: Implement File Injection (AC: 3)

- [ ] Implement `before_exec` phase:
  ```ruby
  def before_exec(context)
    return if input[:tool].tool_files.empty?

    container = context[:container]
    input[:tool].tool_files.each do |tool_file|
      inject_file_into_container(container, tool_file)
    end

    Rails.logger.info("[ToolExecution] Injected #{input[:tool].tool_files.count} files")
  end

  private

  def inject_file_into_container(container, tool_file)
    # Create parent directory
    dir = File.dirname(tool_file.path)
    container.exec(["mkdir", "-p", dir])

    # Write file using base64 encoding (handles binary/special chars)
    encoded = Base64.strict_encode64(tool_file.content || "")
    container.exec(["/bin/sh", "-c", "echo '#{encoded}' | base64 -d > #{tool_file.path}"])
  end
  ```

**Acceptance:** Tool files injected into container before execution

---

### Task 3: Implement Command Execution with Timeout (AC: 4, 5)

- [ ] Override `timeout_for` method:
  ```ruby
  MAX_TOOL_TIMEOUT = 1800  # 30 minutes
  DEFAULT_TOOL_TIMEOUT = 300  # 5 minutes

  def timeout_for(phase)
    return super(phase) unless phase == :exec

    requested = input[:timeout] || DEFAULT_TOOL_TIMEOUT
    [requested.to_i, MAX_TOOL_TIMEOUT].min
  end
  ```
- [ ] Implement `exec` phase:
  ```ruby
  def exec(context)
    timeout = timeout_for(:exec)
    command = build_command(input[:tool], input[:parameters])

    Rails.logger.info("[ToolExecution] Executing: #{command} (timeout: #{timeout}s)")

    start_time = Time.current

    begin
      result = Timeout.timeout(timeout) do
        execute_command_in_container(context[:container], command)
      end

      duration_ms = ((Time.current - start_time) * 1000).to_i

      context[:result] = {
        exit_code: result[:exit_code],
        stdout: truncate_output(result[:stdout]),
        stderr: truncate_output(result[:stderr]),
        duration_ms: duration_ms,
        timed_out: false
      }
    rescue Timeout::Error
      handle_execution_timeout(context, start_time, timeout)
    end
  end
  ```
- [ ] Implement `build_command` (replace {{param}} placeholders):
  ```ruby
  def build_command(tool, parameters)
    command = tool.command.presence || "/bin/sh"

    parameters.each do |key, value|
      command = command.gsub("{{#{key}}}", value.to_s)
    end

    command
  end
  ```
- [ ] Implement `truncate_output` (1MB limit):
  ```ruby
  MAX_OUTPUT_SIZE = 1.megabyte

  def truncate_output(output)
    return "" if output.nil?
    return output if output.bytesize <= MAX_OUTPUT_SIZE

    output.byteslice(0, MAX_OUTPUT_SIZE) + "\n... (truncated, exceeded 1MB limit)"
  end
  ```
- [ ] Implement timeout handler:
  ```ruby
  def handle_execution_timeout(context, start_time, timeout)
    duration_ms = ((Time.current - start_time) * 1000).to_i

    # Kill container immediately
    context[:container].kill rescue nil

    context[:result] = {
      exit_code: 124,  # Standard timeout exit code
      stdout: "",
      stderr: "Tool execution timed out after #{timeout} seconds",
      duration_ms: duration_ms,
      timed_out: true
    }

    Rails.logger.warn("[ToolExecution] TIMEOUT after #{timeout}s")
  end
  ```

**Acceptance:** Tool executes with proper timeout and output limits

---

### Task 4: Implement Artifact Collection (AC: 6)

- [ ] Implement `before_cleanup` phase:
  ```ruby
  def before_cleanup(context)
    tool = input[:tool]
    return if tool.output_paths.blank?

    container = context[:container]
    output_files = {}

    tool.output_paths.each do |path|
      begin
        content = extract_file_from_container(container, path)
        output_files[path] = content if content.present?
      rescue => e
        Rails.logger.warn("[ToolExecution] Failed to extract #{path}: #{e.message}")
      end
    end

    context[:result][:output_files] = output_files
    Rails.logger.info("[ToolExecution] Collected #{output_files.size} output files")
  end

  private

  def extract_file_from_container(container, path)
    tar_data = container.copy(path)
    extract_from_tar(tar_data, File.basename(path))
  end

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
  ```
- [ ] Add `output_paths` field to Tool model (optional, for future use)

**Acceptance:** Output files extracted from container before cleanup

---

### Task 5: Add Resource Limits (AC: 7)

- [ ] Override `build_host_config`:
  ```ruby
  def build_host_config
    super.merge(
      "Memory" => 512 * 1024 * 1024,       # 512MB
      "MemorySwap" => 512 * 1024 * 1024,
      "CpuPeriod" => 100_000,
      "CpuQuota" => 50_000,                # 50% of 1 CPU
      "PidsLimit" => 100,
      "BlkioWeight" => 500
    )
  end
  ```

**Acceptance:** Container has strict resource limits

---

### Task 6: Update ExecuteToolActivity (AC: 8)

- [ ] Simplify `app/temporal/activities/execute_tool_activity.rb`:
  ```ruby
  module Activities
    class ExecuteToolActivity < Base
      def run(input)
        tool = Tool.find(input.tool_id || input["tool_id"])
        project = input.project_id ? Project.find(input.project_id) : nil

        strategy = ContainerStrategies::ToolExecutionStrategy.new(
          tool: tool,
          parameters: input.parameters || input["parameters"] || {},
          project: project,
          timeout: input.timeout || input["timeout"]
        )

        ContainerExecutionService.execute(
          strategy: strategy,
          input: strategy.input
        )
      end
    end
  end
  ```
- [ ] Keep existing activity interface for backward compatibility
- [ ] Update activity timeout to match tool timeout + overhead:
  ```ruby
  activity_timeout -> (input) {
    tool_timeout = input.timeout || 300
    tool_timeout + 300  # Add 5 min for phases overhead
  }
  ```

**Acceptance:** Activity uses new framework, backward compatible

---

### Task 7: Deprecate ToolExecutionService (AC: 8)

- [ ] Add deprecation warning to `app/services/tool_execution_service.rb`:
  ```ruby
  # DEPRECATED: Use ContainerStrategies::ToolExecutionStrategy instead
  # This service will be removed in Epic 8 Phase 5
  class ToolExecutionService
    def self.execute(*args)
      Rails.logger.warn("DEPRECATED: ToolExecutionService.execute called. Use ContainerStrategies::ToolExecutionStrategy")
      # Keep old implementation for now
      # ...existing code...
    end
  end
  ```
- [ ] Document migration path in service comments

**Acceptance:** Old service marked deprecated but still works

---

### Task 8: Write Tests (AC: 9)

- [ ] Test `ToolExecutionStrategy`:
  - Image resolution
  - Config item resolution
  - Env var building
  - File injection
  - Command building with parameter substitution
  - Execution with success
  - Execution with timeout
  - Output truncation
  - Artifact collection
- [ ] Test `ExecuteToolActivity`:
  - Uses new strategy
  - Backward compatible with existing inputs
- [ ] Integration test:
  - Full tool execution end-to-end
  - Compare results with old implementation
- [ ] Update existing tool execution tests

**Acceptance:** All tests pass, >90% coverage

---

## Implementation Notes

### Config Item Resolution Logic

```ruby
# Priority: Project → Company → nil
def find_config_item(name, project, company)
  if project
    ConfigItem.find_by(name: name, scope: project) ||
      ConfigItem.find_by(name: name, scope: company)
  else
    ConfigItem.find_by(name: name, scope: company)
  end
end
```

### Command Execution

```ruby
def execute_command_in_container(container, command)
  stdout_lines, stderr_lines, exit_code = container.exec(
    ["/bin/sh", "-c", command],
    stdout: true,
    stderr: true
  )

  {
    exit_code: exit_code,
    stdout: stdout_lines.join,
    stderr: stderr_lines.join
  }
end
```

### Backward Compatibility

All existing code calling `ToolExecutionService.execute` continues to work. Only `ExecuteToolActivity` is updated to use new framework (activities are internal, not public API).

---

## File List

### New Files
- `app/services/container_strategies/tool_execution_strategy.rb`
- `test/services/container_strategies/tool_execution_strategy_test.rb`

### Modified Files
- `app/temporal/activities/execute_tool_activity.rb` (simplified)
- `app/services/tool_execution_service.rb` (add deprecation warning)
- `test/temporal/activities/execute_tool_activity_test.rb` (updated)

### Future Removal (Story 8.5)
- `app/services/tool_execution_service.rb` (will be deleted)

---

## Dependencies

- Story 8.1 completed (ContainerExecutionService, BaseStrategy)
- Tool model with `docker_image`, `command`, `required_config_items`, `tool_files`
- ConfigItem model for env var resolution

---

## Next Stories

- Story 8.3: Agent Migration (implement AgentAuthStrategy, AgentSessionStrategy)
- Story 8.4: Workflow Unification (UnifiedContainerWorkflow)

---

## Dev Agent Record

**Agent Model:** (to be filled during implementation)

**Completion Notes:** (to be filled during implementation)
