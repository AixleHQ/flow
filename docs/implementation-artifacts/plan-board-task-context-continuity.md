# Board task context continuity implementation plan

> **For agentic workers:** Execute sequentially using `executing-plans`; tests run only inside Docker.

**Goal:** Make a board task's epic and relevant sibling decisions discoverable before an agent changes code.

**Architecture:** Extend the existing `BoardContext` with a bounded epic pointer and explicit retrieval instructions. Add an optional `parent_task_id` filter to the existing paginated, board-scoped `board_list_tasks` tool. Keep comments available through their existing tool so agents fetch current decisions, without copying an entire project's history into every prompt.

**Tech stack:** Rails, Active Record, Minitest, FactoryBot, Docker Compose.

**Spec:** The design agreed in this conversation: task/epic context, focused sibling discovery, board isolation, documentation and regression coverage. Applies to native Flow epic/subtask relationships; external tracker link traversal and cross-task execution scheduling are outside this change.

## Global constraints

- Branch from `develop`, independently of the scoped workflow context PR.
- Never run Ruby, Rails, gem or Node commands on the host.
- Never overlap backend test invocations; use the repository's test flock.
- Preserve paginated responses, existing filters and board-scoped authorization.
- Do not treat a task relationship as execution order or automatically merge branches.
- Do not copy unbounded comments, descriptions or sibling lists into generated context.

## Task 1: Discover an epic's subtasks through the existing board tool

Files: `app/services/internal_tools/board_list_tasks.rb`, `test/services/internal_tools/board_read_tools_test.rb`.

- [x] Add tests that create two epics and subtasks, then assert:
  ```ruby
  data = list_tasks(parent_task_id: epic.id, limit: 1)
  assert_equal 2, data["total"]
  assert_equal [first.id], data["tasks"].map { |task| task["id"] }
  assert data["has_more"]
  ```
  Cover the next page, combined column filters, another board's parent ID returning no tasks, and the public tool schema advertising the parameter.
- [x] Run these tests before implementation and verify the parent filter fails.
- [x] Add an integer schema property for the internal epic ID and filter the existing board scope:
  ```ruby
  scope = scope.where(parent_task_id: params[:parent_task_id]) if params[:parent_task_id].present?
  ```
- [x] Re-run the board read tool tests to verify filtering and existing behavior.

## Task 2: Provide bounded, actionable continuity context

Files: `app/services/context_builders/board_context.rb`, `test/services/context_builders/board_context_test.rb`.

- [x] Add failing tests for a child session receiving its epic ID/number/title and retrieval instructions; an epic session receiving the child-list filter; a standalone task receiving no unrelated epic content; a foreign-board parent never exposing its content.
- [x] Add a regression scenario: an epic's comment changes a requirement; the child session's context identifies the epic, and the real board tools retrieve the complete latest decision and a sibling's evidence.
- [x] Run tests and verify failures reflect missing continuity context.
- [x] Resolve the parent through the current board's task scope. Render its identity plus instructions to read its full description and comments. Provide the exact `parent_task_id` to discover relevant siblings.
- [x] Instruct agents to read current task comments before implementation, reconcile decisions with requirements, report unresolved conflicts and verify prerequisite code on their working branch. Keep existing long-description retrieval behavior.
- [x] Re-run focused tests using:
  ```sh
  docker compose exec -T web env SKIP_COVERAGE=1 flock tmp/.rails-test.lock bin/rails test test/services/context_builders/board_context_test.rb test/services/internal_tools/board_read_tools_test.rb
  ```

## Task 3: Document and verify the user-visible contract

Files: `CHANGELOG.md`, `docs/user-guide/board.md`, `docs/user-guide/prompt-guide.md`, their in-app Docs mirrors, `docs/index.md`.

- [x] Document epic/subtask discovery, on-demand comments and explicit prerequisite branches; correct stale claims about automatically included comments and task movement history.
- [x] Add a short Tasks entry under `[Unreleased]`, and index this plan.
- [x] Run focused tests and RuboCop for modified Ruby files.
- [x] Run `docker compose exec -T web make check_all` and inspect every result. Report existing environment or baseline failures without claiming the gate is green.
- [x] Review the diff, check whitespace and leave the branch ready for review. Do not push or open a PR as part of this request.

## Verification record

- Baseline: 37 tests, 162 assertions, zero failures/errors.
- Red: 45 tests, 7 expected failures and zero errors before implementation.
- Green: 45 tests, 215 assertions, zero failures/errors.
- Final focused suite: 47 tests, 223 assertions, zero failures/errors.
- Modified Ruby files: RuboCop inspected five files with no offenses.
- Independent review and follow-up on the human-author alias: no actionable findings.
- Initial full gate: every check passed except GitHub backend tests (invalid inline key from local environment).
- All 46 GitHub tests pass with GITHUB_APP_PRIVATE_KEY empty for the test process, allowing their disposable PEM fixtures.
- Full backend recheck with that test-only environment: 8,071 tests, 25,147 assertions, zero failures/errors; 93.78% line coverage.
- Human-author filter regression reproduced separately: two failures, zero errors before correction.
- Final backend including the author-filter fix: 8,073 tests, 25,155 assertions, zero failures/errors; 93.78% line coverage.
- Final backend command: `docker compose exec -T web env GITHUB_APP_PRIVATE_KEY= PARALLEL_WORKERS=4 make rails-test`. The inline key is empty only for that process; no local configuration or credentials were changed.
- The other full-gate checks passed: Brakeman, RuboCop, system tests, ESLint, TypeScript, FSD, Vitest, Vite build, watcher tests, worker boot and eager-loading.

## Task 4: Correct the reproduced human-author filter bug

Files: `app/services/internal_tools/board_get_comments.rb`, `test/services/internal_tools/board_read_tools_test.rb`, board documentation mirrors and changelog.

- [x] Reproduce the schema advertising `user` while `TaskComment` stores `human`: the advertised filter returns zero for an existing human decision.
- [x] Add failing tests for the public schema and human/legacy-user retrieval.
- [x] Advertise `human`, retain `user` and normalize the legacy alias to `human` before filtering.
- [x] Run the focused tests and RuboCop after correction.
- [x] Recheck the full backend with its disposable-key test configuration.

No changes to ambiguity policy, soft-budget semantics, semantic output validation or unbounded-comment retrieval are included; the investigation does not measure LLM hallucination rates.
