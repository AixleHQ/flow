# Tool Execution Framework

**Date:** 2026-02-23 (v1)
**Status:** Draft
**Author:** Artem Petrov + AI Analysis
**Supersedes:** Epic 18 internal tools architecture (partially — execution & strategy layers)

---

## Related Documents

| Document | Description |
|----------|-------------|
| [Workflow Architecture](./workflow-architecture.md) | Workflow, Step, SubStep data model and execution flow |
| [Epic 18: Internal Tools](./epics/epic-18-internal-tools.md) | Original internal tools epic (routing, seeds, handlers) |
| [Architecture](./architecture.md) | Core architecture decisions, tech stack |

---

## Overview

Unified framework for executing all tool types through a single strategy hierarchy. Replaces the split execution model (Ruby handlers vs Docker strategies) with a clean three-tier architecture.

Key design principles:
- **One strategy hierarchy** for all container-based tools (custom and internal)
- **App tools** execute in-process, container tools always go through Temporal
- **ToolResult** persists all container execution outputs to Shrine (S3), never in Temporal payload
- **Presigned URLs** for result delivery — agent downloads files via `curl`, never bloats context window

---

## 1. Tool Execution Modes

### 1.1 `execution_mode` field

```ruby
class Tool < ApplicationRecord
  enumerize :execution_mode, in: %i[app container], default: :container
end
```

| Mode | What it means | Examples |
|------|---------------|---------|
| `app` | Executes in Rails process, synchronous, no container | list_sub_steps, mark_sub_step, write_step_note, read_tool_result |
| `container` | Runs in Docker via Temporal workflow, async, produces ToolResult | code_climate, semgrep, custom tools |

### 1.2 Routing

```ruby
class Tool < ApplicationRecord
  def execute(parameters: {}, project: nil, session: nil, timeout: 300)
    case execution_mode.to_sym
    when :app
      InternalToolExecutor.execute(self, parameters, session)
    when :container
      start_container_execution(
        parameters: parameters, project: project,
        session: session, timeout: timeout
      )
    end
  end
end
```

App tools return `{ exit_code:, stdout:, stderr: }` directly.

Container tools create `ToolResult` (state: `processing`), fire Temporal `start_workflow` (async), and return `{ exit_code: 0, stdout: tool_result.execution_id }`. Agent uses `read_tool_result` to fetch status and download URLs later.

---

## 2. Strategy Hierarchy

```
ContainerStrategies::BaseStrategy          (existing — generic phases, cleanup, runtime)
  │
  ├── AgentBaseStrategy                    (existing — agent containers)
  │     ├── AgentAuthStrategy
  │     └── AgentSessionStrategy
  │
  └── ToolStrategy                         (NEW — shared base for ALL tool execution)
        │
        │  Provides: phase_config, start_container, exec,
        │            timeout handling, result persistence to ToolResult
        │
        ├── CustomToolStrategy             (NEW — replaces ToolExecutionStrategy)
        │     Data from: Tool model (docker_image, command, tool_files)
        │     Security: sandboxed (no docker socket, limited resources)
        │     Output: stdout/stderr only
        │
        └── InternalToolStrategy           (NEW — DSL-based definitions)
              Data from: DSL `define` blocks
              Security: per-definition (can mount docker socket, bind paths)
              Output: stdout/stderr + files from container
```

### 2.1 ToolStrategy (shared base)

All tool containers share identical lifecycle: pull → create → start → wait → persist result → cleanup.

```ruby
module ContainerStrategies
  class ToolStrategy < BaseStrategy
    DEFAULT_TIMEOUT = 300
    MAX_TIMEOUT = 1800
    TIMEOUT_EXIT_CODE = 124

    def phase_config(phase)
      case phase
      when :exec    then { timeout: exec_timeout }
      when :cleanup then { timeout: 60, always: true }
      else               { timeout: 120 }
      end
    end

    def before_create_container(**)
      {
        image: resolve_image,
        cmd: build_cmd,
        working_dir: build_working_dir,
        env_vars: build_env_vars,
        labels: build_labels,
        host_config: build_host_config
      }
    end

    def start_container(container_id:, **)
      container = resolve_container(container_id)
      runtime.start_container(container)
      {}
    end

    def exec(container_id:, **)
      container = resolve_container(container_id)
      start_time = Time.current

      begin
        Timeout.timeout(exec_timeout) do
          wait_result = runtime.wait_container(container)
          exit_code = wait_result["StatusCode"] || wait_result[:StatusCode] || -1
          logs = runtime.container_logs(container)
          duration_ms = ms_since(start_time)

          persist_result(exit_code:, stdout: logs[:stdout].to_s,
                         stderr: logs[:stderr].to_s, duration_ms:)

          { tool_result_id: input[:tool_result_id], exit_code:, status: "done" }
        end
      rescue Timeout::Error
        handle_timeout(container, start_time)
      end
    end

    private

    def exec_timeout
      [input[:timeout] || DEFAULT_TIMEOUT, MAX_TIMEOUT].min
    end

    def persist_result(exit_code:, stdout:, stderr:, duration_ms:, error_msg: nil)
      tr = ToolResult.find(input[:tool_result_id])
      tr.complete!(exit_code:, stdout:, stderr:, duration_ms:, error: error_msg)
    end

    def handle_timeout(container, start_time)
      container.kill rescue nil
      logs = runtime.container_logs(container) rescue { stdout: "", stderr: "" }
      duration_ms = ms_since(start_time)

      persist_result(exit_code: TIMEOUT_EXIT_CODE, stdout: logs[:stdout].to_s,
                     stderr: logs[:stderr].to_s, duration_ms:,
                     error_msg: "Timed out after #{exec_timeout}s")

      { tool_result_id: input[:tool_result_id], exit_code: TIMEOUT_EXIT_CODE, status: "failed" }
    end

    def ms_since(start_time)
      ((Time.current - start_time) * 1000).to_i
    end
  end
end
```

### 2.2 CustomToolStrategy

Replaces existing `ToolExecutionStrategy`. Data comes from `Tool` model fields.

```ruby
module ContainerStrategies
  class CustomToolStrategy < ToolStrategy
    def before_create_container(**)
      tool = input[:tool]
      raise ArgumentError, "Tool requires docker_image" if tool.docker_image.blank?
      super
    end

    def resolve_image = input[:tool].docker_image
    def build_working_dir = "/workspace"

    def build_cmd
      tool = input[:tool]
      command = interpolate_command(tool.command || "/bin/sh", input[:parameters] || {})

      if tool.tool_files.any?
        setup = tool.tool_files.map { |tf| file_setup_cmd(tf) }
        ["/bin/sh", "-c", (setup + [command]).join(" && ")]
      else
        ["/bin/sh", "-c", command]
      end
    end

    def build_env_vars
      env = {}
      (input[:parameters] || {}).each { |k, v| env[k.to_s.upcase.gsub(/[^A-Z0-9_]/, "_")] = v.to_s }
      env.merge!(resolve_config_items)
      inject_project_env(env)
      env.map { |k, v| "#{k}=#{v}" }
    end

    def build_labels
      tool = input[:tool]
      { "palad.type" => "tool_execution",
        "palad.tool_id" => tool.id.to_s,
        "palad.tool_name" => tool.name }
    end

    def build_host_config = build_host_config_with_limits

    private

    # ... interpolate_command, file_setup_cmd, resolve_config_items, inject_project_env
    # (moved from current ToolExecutionStrategy, no logic changes)
  end
end
```

**Security:** No bind mounts, no docker socket. `build_host_config_with_limits` applies Settings-based memory/CPU/pids limits.

**Output:** Stdout/stderr only. No file collection from container.

### 2.3 InternalToolStrategy (DSL)

Declarative tool definitions. One class, many tools.

```ruby
module ContainerStrategies
  class InternalToolStrategy < ToolStrategy

    # --- DSL Definition ---

    class Definition
      attr_reader :name, :opts

      def initialize(name)
        @name = name
        @opts = {
          timeout: 300, memory: 1.gigabyte, cpu_quota: 50_000,
          working_dir: "/workspace", docker_socket: false,
          output_files: []
        }
      end

      def image(v)         = tap { @opts[:image] = v }
      def timeout(v)       = tap { @opts[:timeout] = v }
      def memory(v)        = tap { @opts[:memory] = v }
      def cpu_quota(v)     = tap { @opts[:cpu_quota] = v }
      def working_dir(v)   = tap { @opts[:working_dir] = v }
      def docker_socket!   = tap { @opts[:docker_socket] = true }
      def output_files(v)  = tap { @opts[:output_files] = v }

      def cmd(&block)      = tap { @opts[:cmd] = block }
      def env(&block)      = tap { @opts[:env] = block }
      def binds(&block)    = tap { @opts[:binds] = block }
      def prepare(&block)  = tap { @opts[:prepare] = block }
    end

    # --- Registry ---

    class << self
      def registry = @registry ||= {}

      def define(name, &block)
        defn = Definition.new(name)
        defn.instance_eval(&block)
        registry[name.to_s] = defn
      end

      def build_for(name, params:, session:, tool_result_id:, timeout: nil)
        defn = registry[name.to_s]
        raise ArgumentError, "No internal tool definition: #{name}" unless defn

        prepared = run_prepare(defn, params, session)
        new(prepared.merge(
          definition: defn,
          tool_result_id: tool_result_id,
          timeout: timeout || defn.opts[:timeout]
        ))
      end

      private

      def run_prepare(defn, params, session)
        base = params.symbolize_keys.merge(session: session)
        prep = defn.opts[:prepare]
        prep ? prep.call(base).symbolize_keys : base
      end
    end

    # --- Tool Definitions ---

    define :code_climate do
      image "codeclimate/codeclimate"
      timeout 600
      memory 2.gigabytes
      cpu_quota 100_000
      working_dir "/code"
      docker_socket!

      prepare { |input|
        repo = input[:session].repositories.find(input[:repository_id])
        repo_path = RepoCloneService.ensure_cloned(repo)
        CodeClimateConfigWriter.ensure_config(repo_path, input[:engines])
        input.merge(repo_path: repo_path)
      }

      cmd { |input|
        c = ["analyze", "-f", input[:format] || "json"]
        input[:engines]&.split(",")&.each { |e| c += ["-e", e.strip] }
        c
      }

      env { |input|
        { "CODECLIMATE_CODE" => input[:repo_path] }
      }

      binds { |input|
        [
          "#{input[:repo_path]}:/code:ro",
          "/var/run/docker.sock:/var/run/docker.sock",
          "/tmp/cc:/tmp/cc"
        ]
      }
    end

    # --- Phase overrides ---

    def resolve_image = defn.opts[:image]
    def build_working_dir = defn.opts[:working_dir]
    def build_cmd = resolve_callable(defn.opts[:cmd])

    def build_env_vars
      hash = resolve_callable(defn.opts[:env]) || {}
      hash.map { |k, v| "#{k}=#{v}" }
    end

    def build_labels
      { "palad.type" => "internal_tool", "palad.tool" => defn.name.to_s }
    end

    def build_host_config
      cfg = defn.opts
      hc = base_host_config.merge(
        "Memory" => cfg[:memory], "MemorySwap" => cfg[:memory],
        "CpuPeriod" => 100_000, "CpuQuota" => cfg[:cpu_quota]
      )
      binds_val = resolve_callable(cfg[:binds]) || []
      if cfg[:docker_socket]
        binds_val << "/var/run/docker.sock:/var/run/docker.sock"
        binds_val.uniq!
      end
      hc["Binds"] = binds_val if binds_val.any?
      hc
    end

    # Internal tools can collect files from container
    def before_cleanup(container_id: nil, **)
      paths = defn.opts[:output_files]
      return {} if paths.blank? || container_id.blank?

      container = resolve_container(container_id)
      tr = ToolResult.find(input[:tool_result_id])
      tr.attach_output_files(container, paths, runtime)
      {}
    end

    private

    def defn = input[:definition]
    def exec_timeout = defn.opts[:timeout]

    def resolve_callable(val)
      val.is_a?(Proc) ? val.call(input) : val
    end
  end
end
```

---

## 3. ToolResult Model

Persists all container execution outputs. No text columns in DB — everything heavy goes to Shrine/S3.

### 3.1 Schema

```ruby
class CreateToolResults < ActiveRecord::Migration[7.2]
  def change
    create_table :tool_results do |t|
      t.string :execution_id, null: false, index: { unique: true }
      t.string :state, null: false, default: "processing"
      t.references :tool, null: false, foreign_key: true
      t.references :terminal_session, foreign_key: true
      t.references :step_run, foreign_key: true
      t.integer :exit_code
      t.string :error
      t.integer :duration_ms
      t.text :stdout_data    # shrine
      t.text :stderr_data    # shrine
      t.text :result_data_data  # shrine (parsed JSON)
      t.text :output_data    # shrine (files archive)
      t.timestamps
    end
  end
end
```

### 3.2 Model

```ruby
class ToolResult < ApplicationRecord
  include ToolResultUploader::Attachment(:stdout)
  include ToolResultUploader::Attachment(:stderr)
  include ToolResultUploader::Attachment(:result_data)
  include ToolResultUploader::Attachment(:output)

  belongs_to :tool
  belongs_to :terminal_session, optional: true
  belongs_to :step_run, optional: true

  validates :execution_id, presence: true, uniqueness: true
  validates :state, presence: true, inclusion: {
    in: %w[processing completed failed expired]
  }

  scope :stale, ->(age) { where(state: %w[completed failed]).where("created_at < ?", age.ago) }

  def self.generate_id
    "tr-#{SecureRandom.hex(12)}"
  end

  def complete!(exit_code:, stdout:, stderr:, duration_ms:, error: nil)
    attrs = {
      state: error.nil? && exit_code == 0 ? :completed : :failed,
      exit_code: exit_code,
      error: error || (exit_code != 0 ? "Exited with code #{exit_code}" : nil),
      duration_ms: duration_ms
    }

    attrs[:stdout] = string_to_io(stdout, "stdout.txt", "text/plain") if stdout.present?
    attrs[:stderr] = string_to_io(stderr, "stderr.txt", "text/plain") if stderr.present?

    parsed = try_parse_json(stdout)
    if parsed
      attrs[:result_data] = string_to_io(parsed.to_json, "result_data.json", "application/json")
    end

    update!(attrs)
  end

  def attach_output_files(container, paths, runtime)
    collected = {}
    paths.each do |path|
      content = read_file_from_container(container, path, runtime)
      collected[File.basename(path)] = content if content.present?
    end
    return if collected.empty?

    archive = TarGzPacker.pack(collected)
    self.output = { io: StringIO.new(archive), filename: "output.tar.gz",
                    content_type: "application/gzip" }
    save!
  end

  private

  def string_to_io(content, filename, content_type)
    { io: StringIO.new(content), filename: filename, content_type: content_type }
  end

  def try_parse_json(text)
    return nil if text.blank?
    parsed = JSON.parse(text)
    parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def read_file_from_container(container, path, runtime)
    result = runtime.exec(container, ["cat", path])
    return nil unless result[2].zero?
    result[0].join
  rescue StandardError
    nil
  end
end
```

### 3.3 Uploader

```ruby
class ToolResultUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data

  def generate_location(io, record: nil, name: nil, **)
    return super unless record.is_a?(ToolResult)

    "tool_results/#{record.execution_id}/#{name}/#{super(io).split('/').last}"
  end
end
```

### 3.4 States

```
processing  →  completed    (exit_code == 0, no error)
     │
     └──────→  failed       (exit_code != 0, or timeout, or crash)
                              error: "Timed out after 600s"
                              error: "Exited with code 1"
                              error: "Container OOM killed"

completed  →  expired       (cleanup job)
failed     →  expired       (cleanup job)
```

### 3.5 Cleanup

Configurable retention, no `expires_at` column:

```ruby
class ToolResultCleanupJob < ApplicationJob
  RETENTION = -> { (Settings.tool_results&.retention_days || 30).days }

  def perform
    ToolResult.stale(RETENTION.call).find_each do |tr|
      tr.stdout&.delete
      tr.stderr&.delete
      tr.result_data&.delete
      tr.output&.delete
      tr.update!(state: :expired, stdout_data: nil, stderr_data: nil,
                 result_data_data: nil, output_data: nil)
    end
  end
end
```

---

## 4. Serializer

```ruby
class ToolResultSerializer < ApplicationSerializer
  URL_TTL = 3600

  attributes :execution_id, :state, :exit_code, :error, :duration_ms, :created_at

  attribute :tool_name do
    object.tool.name
  end

  attribute :stdout_url do
    object.stdout&.url(expires_in: URL_TTL)
  end

  attribute :stdout_size do
    object.stdout&.metadata&.dig("size")
  end

  attribute :stderr_url do
    object.stderr&.url(expires_in: URL_TTL)
  end

  attribute :stderr_size do
    object.stderr&.metadata&.dig("size")
  end

  attribute :result_data_url do
    object.result_data&.url(expires_in: URL_TTL)
  end

  attribute :result_data_size do
    object.result_data&.metadata&.dig("size")
  end

  attribute :output_url do
    object.output&.url(expires_in: URL_TTL)
  end

  attribute :output_size do
    object.output&.metadata&.dig("size")
  end
end
```

Nil attachments produce nil attributes — serializer returns only what exists. Agent receives ~200-400 bytes through MCP.

---

## 5. MCP Integration

### 5.1 tools/call handler

```ruby
# In action_mcp_dynamic_tools.rb

def execute_tool(tool, arguments, session)
  if tool.execution_mode_app?
    # Sync: direct result
    tool.execute(parameters: arguments || {}, project: session.project, session: session)
  else
    # Async: create ToolResult, start Temporal workflow, return execution_id
    tool_result = ToolResult.create!(
      tool: tool,
      terminal_session: session,
      step_run: session.step_run,
      execution_id: ToolResult.generate_id,
      state: :processing
    )

    tool.execute(
      parameters: arguments || {},
      project: session.project,
      session: session,
      tool_result_id: tool_result.id
    )

    { exit_code: 0, stdout: tool_result.execution_id }
  end
end
```

### 5.2 Response format

**App tool** (sync) — result directly in MCP response:

```json
{
  "content": [{ "type": "text", "text": "[{\"id\":1,\"name\":\"Overview\",\"status\":\"completed\"}]" }]
}
```

**Container tool** (async) — execution_id only:

```json
{
  "content": [{ "type": "text", "text": "tr-a1b2c3d4e5f6e7a8" }]
}
```

### 5.3 read_tool_result (app tool)

```ruby
module InternalTools
  class ReadToolResult < Base
    def execute
      tr = ToolResult.find_by(execution_id: params[:tool_result_id])
      return error("Tool result not found") unless tr

      success(ToolResultSerializer.new(tr).to_json)
    end
  end
end
```

Agent receives serialized metadata with presigned download URLs:

```json
{
  "execution_id": "tr-a1b2c3d4e5f6e7a8",
  "tool_name": "code_climate",
  "state": "completed",
  "exit_code": 0,
  "duration_ms": 3200,
  "stdout_url": "https://minio:9000/store/tool_results/tr-.../stdout/stdout.txt?X-Amz-Expires=3600&...",
  "stdout_size": 524288,
  "result_data_url": "https://minio:9000/store/tool_results/tr-.../result_data/result_data.json?...",
  "result_data_size": 245000
}
```

Agent then downloads via shell:
```bash
curl -sS -o /workspace/code_climate.json "<result_data_url>"
```

URLs expire in 1 hour. Agent can call `read_tool_result` again to get fresh URLs.

---

## 6. Tool#execute — Updated Routing

```ruby
class Tool < ApplicationRecord
  enumerize :execution_mode, in: %i[app container], default: :container

  WORKFLOW_TIMEOUT = 3600

  def execute(parameters: {}, project: nil, session: nil, timeout: 300, tool_result_id: nil)
    case execution_mode.to_sym
    when :app
      InternalToolExecutor.execute(self, parameters, session)
    when :container
      start_container_execution(
        parameters:, project:, session:, timeout:, tool_result_id:
      )
    end
  end

  private

  def start_container_execution(parameters:, project:, session:, timeout:, tool_result_id:)
    strategy = build_strategy(parameters:, project:, session:, timeout:, tool_result_id:)
    workflow_id = "tool-exec-#{id}-#{SecureRandom.hex(8)}"

    TemporalService.start_workflow(
      WorkflowService.container_workflow,
      { tool_id: id, tool_result_id: tool_result_id,
        parameters: parameters, project_id: project&.id,
        timeout: timeout, manifest: strategy.build_manifest },
      id: workflow_id,
      execution_timeout: WORKFLOW_TIMEOUT
    )
  end

  def build_strategy(parameters:, project:, session:, timeout:, tool_result_id:)
    if custom?
      ContainerStrategies::CustomToolStrategy.new(
        tool: self, parameters: parameters, project: project,
        timeout: timeout, tool_result_id: tool_result_id
      )
    else
      ContainerStrategies::InternalToolStrategy.build_for(
        name, params: parameters, session: session,
        tool_result_id: tool_result_id, timeout: timeout
      )
    end
  end
end
```

---

## 7. Security Model

| Aspect | Custom tools | Internal container tools |
|--------|-------------|------------------------|
| Docker socket | **Never** | Per-definition (`docker_socket!`) |
| Bind mounts | **None** | Per-definition (`binds` block) |
| Network | palad docker network | palad docker network |
| Memory/CPU | Settings-based limits | Per-definition (can override) |
| Image source | User-specified | Hardcoded in DSL |
| File collection | **No** (stdout only) | **Yes** (`output_files`) |

Custom tools are sandboxed: no host filesystem access, no docker socket, resource-limited. Internal tools can be privileged because definitions are code-reviewed and hardcoded.

---

## 8. What Gets Deleted

After migration to this framework:

| File | Reason |
|------|--------|
| `app/services/container_strategies/tool_execution_strategy.rb` | Replaced by `CustomToolStrategy` |
| `app/services/container_strategies/code_climate_strategy.rb` | Replaced by DSL definition in `InternalToolStrategy` |
| `app/services/internal_tools/code_climate.rb` | Replaced by DSL definition + prepare block |

`InternalToolExecutor` stays — still routes `app`-mode tools to Ruby handler classes.

`InternalTools::Base` stays — base class for app-mode handlers (list_sub_steps, mark_sub_step, write_step_note, read_tool_result).

---

## 9. Adding a New Tool

### New custom tool (user-created)

No code changes. User creates Tool record via UI:
- `docker_image`, `command`, `tool_files` — standard fields
- `execution_mode: :container` (default)
- `kind: :custom`

### New internal app tool

1. Create handler class in `app/services/internal_tools/my_tool.rb`
2. Add seed with `execution_mode: :app, kind: :internal`

### New internal container tool

1. Add `define :my_tool` block in `InternalToolStrategy`
2. Add seed with `execution_mode: :container, kind: :internal`

```ruby
# Example: adding Semgrep (15 lines)
define :semgrep do
  image "returntocorp/semgrep"
  timeout 300
  memory 1.gigabyte
  working_dir "/src"

  prepare { |input|
    repo = input[:session].repositories.find(input[:repository_id])
    input.merge(repo_path: RepoCloneService.ensure_cloned(repo))
  }

  binds { |input| ["#{input[:repo_path]}:/src:ro"] }
  cmd { |_| ["scan", "--json", "--config=auto", "/src"] }
end
```

---

## 10. Temporal Payload

Temporal workflow payload is always small:

**Input:**
```ruby
{ tool_id: 42, tool_result_id: 123, parameters: { repository_id: 1 },
  project_id: 5, timeout: 600, manifest: { ... } }
```

**Activity result (from exec phase):**
```ruby
{ tool_result_id: 123, exit_code: 0, status: "done" }
```

All heavy data (stdout, stderr, files) goes to ToolResult → Shrine → S3. Temporal never sees more than ~500 bytes per activity.

---

## 11. Migration Plan

### Database

1. Add `execution_mode` column to `tools` table
2. Create `tool_results` table
3. Update existing internal tool seeds: `execution_mode: :app` for workflow tools, `:container` for code_climate
4. Seed `read_tool_result` as new internal app tool

### Code

1. Create `ToolResultUploader`
2. Create `ToolResult` model
3. Create `ToolResultSerializer`
4. Create `ContainerStrategies::ToolStrategy` (extract shared logic)
5. Create `ContainerStrategies::CustomToolStrategy` (move custom logic)
6. Create `ContainerStrategies::InternalToolStrategy` (DSL + code_climate definition)
7. Create `InternalTools::ReadToolResult`
8. Update `Tool#execute` routing
9. Update `action_mcp_dynamic_tools.rb` (async for container tools)
10. Delete `ToolExecutionStrategy`, `CodeClimateStrategy`, `InternalTools::CodeClimate`
11. Update tests

---

## 12. Open Questions

| # | Question | Status |
|---|----------|--------|
| 1 | Container-accessible URL for presigned S3 links (minio host from inside docker network) | Need to verify `Settings.container_asset_host` works for presigned URLs |
| 2 | TarGzPacker utility — new class or use existing gem? | TBD |
| 3 | Should `read_tool_result` poll (agent calls multiple times) or should we add a `wait_for_tool_result` with timeout? | Agent polls, simpler |
| 4 | Shrine multiple attachments on one model — any gotchas with `pretty_location` plugin? | Test during implementation |

---

_Document v1, 2026-02-23_
