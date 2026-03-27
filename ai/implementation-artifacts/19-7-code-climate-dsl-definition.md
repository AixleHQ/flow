# Story 19.7: Code Climate as DSL Definition

Status: ready-for-dev

## Story

As a developer,
I want Code Climate analysis defined via InternalToolStrategy DSL,
so that the separate CodeClimateStrategy and InternalTools::CodeClimate classes are eliminated.

## Acceptance Criteria

1. `InternalToolStrategy.define :code_climate` block added with: image `codeclimate/codeclimate`, timeout 600, memory 2GB, cpu_quota 100k
2. `docker_socket!` enabled (Code Climate spawns engine sub-containers)
3. `prepare` block: resolve repository, ensure clone, generate `.codeclimate.yml` config
4. `cmd` block: `["analyze", "-f", format, "-e", engines...]`
5. `env` block: `CODECLIMATE_CODE` pointing to repo path
6. `binds` block: repo read-only, docker socket, shared `/tmp/cc`
7. Seed updated: `code_climate` tool gets `execution_mode: :container`
8. `RepoCloneService` extracted from existing `InternalTools::CodeClimate#ensure_cloned` logic
9. `CodeClimateConfigWriter` extracted from existing `ensure_config` logic

## Tasks / Subtasks

- [ ] Task 1: Extract RepoCloneService (AC: #8)
  - [ ] Create `app/services/repo_clone_service.rb`
  - [ ] `.ensure_cloned(repo)` — returns local path of cloned repo
  - [ ] Move git clone/pull logic from `InternalTools::CodeClimate`
- [ ] Task 2: Extract CodeClimateConfigWriter (AC: #9)
  - [ ] Create `app/services/code_climate_config_writer.rb`
  - [ ] `.ensure_config(repo_path, engines)` — writes `.codeclimate.yml` if not present
  - [ ] Move config generation logic from `InternalTools::CodeClimate`
- [ ] Task 3: DSL definition (AC: #1-#6)
  - [ ] Add `define :code_climate` block inside `InternalToolStrategy`
  - [ ] Image, timeout, memory, cpu_quota, working_dir
  - [ ] `docker_socket!`
  - [ ] `prepare` block — uses RepoCloneService and CodeClimateConfigWriter
  - [ ] `cmd` block — analyze command with format and engines
  - [ ] `env` block — CODECLIMATE_CODE
  - [ ] `binds` block — repo, docker.sock, /tmp/cc
- [ ] Task 4: Update seed (AC: #7)
  - [ ] `db/seeds/code_report.rb` — set `execution_mode: :container` on code_climate tool
- [ ] Task 5: Tests
  - [ ] Test RepoCloneService.ensure_cloned
  - [ ] Test CodeClimateConfigWriter.ensure_config
  - [ ] Test code_climate DSL definition is registered
  - [ ] Test build_for(:code_climate) produces correct strategy config
  - [ ] Test prepare block enriches input with repo_path

## Dev Notes

- `InternalTools::CodeClimate` and `CodeClimateStrategy` are NOT deleted here — that's Story 19.13
- DSL definition lives inside `internal_tool_strategy.rb` file
- `RepoCloneService` may be reused by future tools (e.g., Semgrep)
- Code Climate requires running as privileged (docker.sock) because engines are Docker containers themselves

### Project Structure Notes

- `app/services/repo_clone_service.rb` — new file
- `app/services/code_climate_config_writer.rb` — new file
- `app/services/container_strategies/internal_tool_strategy.rb` — modify (add define block)
- `db/seeds/code_report.rb` — modify existing

### References

- [Source: ai/tool-execution-framework.md#2.3, define :code_climate block] — DSL definition
- [Source: app/services/internal_tools/code_climate.rb] — logic to extract
- [Source: app/services/container_strategies/code_climate_strategy.rb] — logic to replace
