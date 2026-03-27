# Story 14.3: Repository Clone at Session Injection

Status: done

## Story

As a user,
I want configured repositories to be automatically cloned into my agent session container,
so that the agent has access to fresh code context.

## Acceptance Criteria

1. ~~**Session config extension** — `session_config` accepts `repository_ids: [...]`.~~ **DONE in 14-2** — `repository_ids` already in `ALLOWED_SESSION_CONFIG_KEYS`, accessor exists, permitted in controller.
2. **SessionContextService extension** — New step `inject_repositories` in context assembly: for each selected repository, generate a fresh installation access token and perform shallow clone into container.
3. **Shallow clone** — `git clone --depth=1 --branch={source_branch} https://x-access-token:{token}@github.com/{full_name}.git /workspace/repos/{repo_name}` — minimal history, always fresh.
4. **Multiple repos** — Support cloning multiple repositories into separate subdirectories under `/workspace/repo/`.
5. **Clone failure handling** — If clone fails (auth error, repo not found, network), log error and continue session start. Report failed repos in `session.metadata["failed_repos"]`, don't block session.
6. **Context file mention** — `build_context_content` includes a section listing cloned repositories and their paths + purpose.
7. ~~**Session Launch UI** — Repository picker in New Session form.~~ **DONE in 14-2** — Multi-select Autocomplete in `SessionLaunchWidget`, sends `repositoryIds` in `sessionConfig`.

## Tasks / Subtasks

- [x] Task 1: `inject_repositories` in SessionContextService (AC: #2, #3, #4, #5)
  - [x] 1.1 Add `inject_repositories(container_id, session)` method to `SessionContextService`
  - [x] 1.2 Resolve `Repository` records from `session.repository_ids`, include `:integration`
  - [x] 1.3 Group repositories by `integration_id` — one token per integration (reuse across repos from same org)
  - [x] 1.4 For each integration group: call `Github::TokenService.new(integration).generate_installation_token` once
  - [x] 1.5 For each repository: run `git clone --depth=1 --branch={source_branch} https://x-access-token:{token}@github.com/{full_name}.git /workspace/repos/{repo_name}` via `runtime.exec`
  - [x] 1.6 Set ownership of cloned dir to adapter's `tmpfs_uid` (combined in clone command with `chown -R`)
  - [x] 1.7 Update `repository.last_fetched_at` after successful clone
  - [x] 1.8 On failure: log error, add to `session.metadata["failed_repos"]` array, continue with next repo

- [x] Task 2: Wire into assembly pipeline (AC: #2)
  - [x] 2.1 Add `measure_step("repositories") { inject_repositories(container_id, session) }` to `assemble_session_context` — Step 7 after assets

- [x] Task 3: Context file section (AC: #6)
  - [x] 3.1 Add `build_repositories_section(session)` to `SessionContextService`
  - [x] 3.2 Returns markdown section listing each cloned repo: path, full_name, source_branch, purpose
  - [x] 3.3 Wire into `build_context_content` — Section 6 before General instructions

- [x] Task 4: Tests (AC: all)
  - [x] 4.1 Unit test for `inject_repositories` — mock runtime.exec, verify git clone command format, token reuse per integration
  - [x] 4.2 Test clone failure handling — verify error logged, metadata updated, other repos still cloned
  - [x] 4.3 Test `build_repositories_section` output format
  - [x] 4.4 Test `repository_ids` accessor on TerminalSession

## Dev Notes

### Token Lifecycle — One Token Per Integration

Critical optimization: group repos by `integration_id` and generate ONE token per integration. Example with 3 repos from 2 orgs:

```ruby
repos = Repository.where(id: session.repository_ids).includes(:integration)
repos.group_by(&:integration_id).each do |_integration_id, group_repos|
  integration = group_repos.first.integration
  token = Github::TokenService.new(integration).generate_installation_token
  group_repos.each { |repo| clone_repo(container_id, repo, token, uid) }
end
```

### Clone Command Pattern

```bash
git clone --depth=1 --branch=main https://x-access-token:ghs_xxxx@github.com/acme/my-app.git /workspace/repos/my-app
```

Use `exec_in_container` (same pattern as other container ops in SessionContextService). The token is embedded in the URL — no credential helper needed. Token lives 1h, clone takes seconds.

### Field Rename: `source_branch` (not `default_branch`)

Story 14.2 renamed the field from `default_branch` to `source_branch`. Use `repo.source_branch` for the `--branch` flag.

### Failure Handling Pattern

```ruby
def clone_repo(container_id, repo, token, uid)
  clone_url = "https://x-access-token:#{token}@github.com/#{repo.full_name}.git"
  target_path = "/workspace/repos/#{repo.repo_name}"
  cmd = "git clone --depth=1 --branch=#{repo.source_branch} #{clone_url} #{target_path}"
  
  exec_in_container(container_id, cmd, uid)
  repo.update_column(:last_fetched_at, Time.current)
  Rails.logger.info("[SessionContext] Cloned repository: #{repo.full_name} → #{target_path}")
rescue => e
  Rails.logger.error("[SessionContext] Failed to clone #{repo.full_name}: #{e.message}")
  record_failed_repo(session, repo, e.message)
end
```

### Context File Section Example

```markdown
## Available Repositories

The following code repositories have been cloned into this session:

| Repository | Path | Branch | Purpose |
|---|---|---|---|
| acme/my-app | /workspace/repos/my-app | main | Our main Rails application |
| acme/infra | /workspace/repos/infra | develop | Infrastructure as code (Terraform) |
```

### Existing Patterns to Follow

**SessionContextService** — `web/app/services/session_context_service.rb`:
- `inject_assets` (line 436) — pattern for resolving IDs, iterating, writing to container, logging
- `build_tool_descriptions` — pattern for context file section generation
- `assemble_session_context` (line 25) — where to wire new step
- `build_context_content` (line 239) — where to add repos section

**Container exec pattern:**
```ruby
# exec_in_container runs a command inside the Docker container
exec_in_container(container_id, command, uid)
```

**Adapter pattern:**
```ruby
adapter = adapter_for(session)
uid = adapter.tmpfs_uid  # User ID for file ownership
```

### Dependencies

- **Story 14.1** — `Github::TokenService` (generates installation access tokens)
- **Story 14.2** — `Repository` model with `source_branch`, `full_name`, `repo_name`, `integration` association

### Project Structure Notes

**Files to modify:**
- `web/app/services/session_context_service.rb` — add `inject_repositories`, `build_repositories_section`, wire into assembly

**No new files needed** — this is purely an extension of the existing `SessionContextService`.

### References

- [Source: ai/epics/epic-14-external-integrations-phase-7.md#Story 14.3]
- [Pattern: web/app/services/session_context_service.rb#inject_assets]
- [Pattern: web/app/services/session_context_service.rb#build_context_content]
- [Dependency: 14-1-integration-model-github-app-credentials.md]
- [Dependency: 14-2-repository-model-crud.md]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Completion Notes List
- All 4 tasks implemented in a single file modification (`SessionContextService`)
- Token reuse per integration group avoids redundant API calls
- Clone + chown combined in one `sh -c` command to minimize container exec calls
- Failed repos tracked in `session.metadata["failed_repos"]` — session start not blocked
- Context file section excludes failed repos, shows dash for missing purpose
- 10 new tests added, all passing (91 total, 250 assertions)

### File List
- `web/app/services/session_context_service.rb` — added `inject_repositories`, `clone_repository`, `record_failed_repo`, `build_repositories_section`; wired into `assemble_session_context` (Step 7) and `build_context_content` (Section 6)
- `web/test/services/session_context_service_test.rb` — 10 new tests for inject_repositories, build_repositories_section, repository_ids accessor
