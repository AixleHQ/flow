# Story 18.6: Code Climate Tool + Container Strategy

Status: review

## Story

As an agent,
I want to run Code Climate static analysis on a repository,
so that I can include automated quality metrics in code reports.

## Acceptance Criteria

1. Handler `InternalTools::CodeClimate` accepts `repository_id` (required), `engines` (optional), `format` (optional: json/text, default: json)
2. Resolves repository from project, clones to temp directory if needed
3. `CodeClimateStrategy` creates Docker container with:
   - Image: `codeclimate/codeclimate`
   - Bind mounts: repo → `/code`, Docker socket, `/tmp/cc`
   - Memory limit: 2GB, CPU quota
4. Generates default `.codeclimate.yml` if not present in repo
5. Returns analysis output (JSON or text)
6. Container cleaned up after execution (even on error)
7. Timeout: 10 minutes
8. Returns error if repository not found or not accessible from session project

## Tasks / Subtasks

- [x] Task 1: Create `CodeClimateStrategy` (AC: #3, #6, #7)
  - [x] Create `app/services/container_strategies/code_climate_strategy.rb`
  - [x] Extend `BaseStrategy`
  - [x] Override `resolve_image` → `"codeclimate/codeclimate"`
  - [x] Override `build_host_config` → bind mounts (repo path → `/code`, docker socket, `/tmp/cc`)
  - [x] Override `build_cmd` → `["analyze", "-f", format]` + engine flags
  - [x] Override `build_working_dir` → `/code`
  - [x] Set memory_limit: 2GB, cpu_quota: 100_000
  - [x] Cleanup via inherited BaseStrategy#cleanup
- [x] Task 2: Create handler (AC: #1, #2, #4, #5, #8)
  - [x] Create `app/services/internal_tools/code_climate.rb`
  - [x] Resolve repo via `Repository.merged_for_project` + detect by id
  - [x] Clone to `/tmp/aixle-repos/{id}/` using `git clone --depth=1`
  - [x] Generate `.codeclimate.yml` if missing
  - [x] Execute all ContainerService phases sequentially, return output
- [x] Task 3: Default config generation (AC: #4)
  - [x] Generate `.codeclimate.yml` with standard checks enabled
  - [x] If `engines` param provided, add as plugins
  - [x] Write to repo dir only if not already present
- [x] Task 4: Tests (AC: all)
  - [x] Test strategy builds correct Docker config (6 tests)
  - [x] Test handler resolves repo correctly
  - [x] Test default config generation
  - [x] Test error on missing repository
  - [x] Test format_result for success/error paths

## Dev Notes

### Strategy Pattern

Follows existing `ToolExecutionStrategy` pattern but with critical differences:
- **Bind mounts** instead of tool_files base64 injection
- Docker socket mount required (Code Climate spawns engine sub-containers)
- `/tmp/cc` shared volume for intermediate results

```ruby
module ContainerStrategies
  class CodeClimateStrategy < BaseStrategy
    IMAGE = "codeclimate/codeclimate"
    TIMEOUT = 600

    def before_create_container(**)
      {
        image: IMAGE,
        cmd: build_cmd,
        working_dir: "/code",
        host_config: {
          "Binds" => [
            "#{input[:repo_path]}:/code:ro",
            "/var/run/docker.sock:/var/run/docker.sock",
            "/tmp/cc:/tmp/cc"
          ],
          "Memory" => 2.gigabytes,
          "CpuQuota" => 100_000
        },
        env_vars: ["CODECLIMATE_CODE=#{input[:repo_path]}"],
        labels: { "aixle.type" => "internal_tool", "aixle.tool" => "code_climate" }
      }
    end

    private

    def build_cmd
      cmd = ["analyze", "-f", input[:format] || "json"]
      engines = input[:engines]&.split(",")&.map(&:strip)
      engines&.each { |e| cmd += ["-e", e] }
      cmd
    end
  end
end
```

### Repository Clone Path

The handler needs the repo on the **host** filesystem (for Docker bind mount). Options:
1. If repo is already cloned somewhere accessible → reuse path
2. If not → clone to `/tmp/aixle-repos/{repo_id}/` using `Github::TokenService`
3. Clean up temp clone after analysis

### Docker-in-Docker

Code Climate itself spawns engine containers (rubocop, eslint, etc.). Requires:
- Docker socket mount: `/var/run/docker.sock`
- `CODECLIMATE_CODE` env var pointing to host path (for engine sub-container mounts)
- Shared `/tmp/cc` for inter-container communication

### References

- [Source: app/services/container_strategies/tool_execution_strategy.rb] — existing strategy pattern
- [Source: app/services/container_strategies/base_strategy.rb] — base strategy
- [Source: ai/epics/epic-18-internal-tools.md#Story 18.6]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- CodeClimateStrategy: bind mounts repo→/code:ro, docker socket, /tmp/cc; CODECLIMATE_CODE env; 2GB memory; analyze cmd with optional engines
- Handler orchestrates: resolve repo → clone → config → ContainerService phases → format result
- Default config has standard complexity checks; plugins appended from engines param
- 14 tests: strategy config/bind mounts/cmd/labels + handler repo resolution/config gen/error cases

### File List
- app/services/container_strategies/code_climate_strategy.rb (new)
- app/services/internal_tools/code_climate.rb (new)
- test/services/container_strategies/code_climate_strategy_test.rb (new)
- test/services/internal_tools/code_climate_test.rb (new)
