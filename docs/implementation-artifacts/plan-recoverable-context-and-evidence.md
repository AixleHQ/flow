# Recoverable context and completion evidence implementation plan

> Execute sequentially with `executing-plans` and TDD. All runtime commands run inside the Docker web container.

**Goal:** Make shortened context recoverable, comments discoverable by pages, ambiguity handling consistent with failure rules, and opt-in completion evidence mechanically verifiable.

**Architecture:** Add read-only tools alongside the existing compatible APIs. Generated context carries IDs and recovery calls rather than broken JSON fragments. A small completion-evidence service validates successful recorded tool executions belonging to the current session; a workflow flag or session metadata can require these receipts before `finish_session`.

**Tech stack:** Rails, Active Record, Minitest, FactoryBot, existing Tools registry and Docker Compose.

**Scope:** The five remaining improvements requested in this conversation. Branch from local `develop`, independently of the epic-context PR. No claim of measuring or eliminating LLM hallucinations.

## Constraints

- Do not change the legacy `board_get_comments` array response.
- Keep full reads scoped to the current board or workflow run; never use a global ID lookup.
- List bounded previews with an explicit truncation indicator and a full-read path.
- Keep only valid complete JSON inline; omit large structured values with a recovery pointer.
- Never overlap backend tests; use `flock tmp/.rails-test.lock`.
- Never execute Ruby, Rails, gems or Node on the host.
- Evidence enforcement defaults off; validate supplied evidence even when not required.
- Evidence verifies recorded execution state/ownership, not the semantic correctness of arbitrary claims.

## Task 1 — Paginated comment discovery and full reads

Files: `app/services/internal_tools/board_list_comments.rb`, `board_get_comment.rb`, tests under `test/services/internal_tools/`.

- [x] Write and run failing tests for default/max page size, stable `(created_at DESC, id DESC)` order, offsets, filters, preview truncation and full recovery, empty pages and foreign-board IDs.
- [x] Add `board_list_comments(task_id:, limit: 25, offset: 0, tag:, author_type:)` returning `{comments, total, limit, offset, has_more}`. Cap pages at 100 and preview bodies at 400 characters; include `body_truncated` and original `body_length`.
- [x] Add `board_get_comment(task_id:, comment_id:)` returning the complete existing `TaskCommentResource`. Scope both IDs through the current board.
- [x] Accept `human`, compatible `user` alias, `agent` and `system` in the new tool. Existing tools retain their contracts.
- [x] Re-run the new tests and existing board-read tests.

## Task 2 — Recover full workflow results and avoid incomplete JSON

Files: `app/services/internal_tools/get_step_result.rb`, `app/services/context_builders/workflow_context.rb`, `app/services/context_renderer.rb`, related tests.

- [x] Write failing cases for a constraint after character 500, large sub-step JSON, compression removing data, and foreign run/step IDs.
- [x] Add `get_step_result(step_run_id:, sub_step_run_id: optional)`, scoped to `workflow_run.step_runs`; return the full step note and a sub-step index, or one complete sub-step note/data.
- [x] Add stable recovery calls beside shortened notes and all structured-data summaries. For example: `get_step_result(step_run_id: 12, sub_step_run_id: 34)`.
- [x] Replace JSON string truncation with complete inline JSON below the existing size threshold and an explicit recovery line above it.
- [x] Check `→ data:` before the generic long-arrow rule in over-budget compression, so it is removed rather than cut into invalid JSON. Keep recovery lines outside that removable prefix.
- [x] Verify full recovery, valid inline JSON and unchanged basic workflow context behavior.

## Task 3 — Distinguish minor assumptions from essential blockers

Files: `app/services/context_builders/critical_rules.rb`, `session_completion.rb`, related tests.

- [x] Write a failing contract test forbidding unconditional ambiguity/never-stop instructions and requiring explicit missing/conflicting-essential-requirement handling.
- [x] Allow minor, reversible, documented assumptions only. Require consulting available sources; if an essential requirement is unavailable or unresolved conflict prevents safe completion, record the blocker and call `fail_session` in unattended mode.
- [x] Keep non-interactive behavior: no waiting for a human and no partial work reported as successful.
- [x] Re-run both context-builder suites.

## Task 4 — Verify opt-in completion receipts

Files: `app/services/completion_evidence.rb`, `app/services/internal_tools/finish_session.rb`, workflow config/model and personal tools, completion context and tests.

- [x] Write failing tests for required missing evidence, unknown/foreign/pending/failed executions, excessive or malformed IDs, and successful current-session receipts. Check failures leave session state and step note unchanged.
- [x] Add `evidence_execution_ids` (at most 20 unique strings) to `finish_session`.
- [x] Require at least one receipt when workflow config or session metadata contains boolean `completion_evidence_required: true`. Expose the workflow flag through existing `update_workflow`/`get_workflow` tools and whitelist it in the model.
- [x] Validate each ID against `ToolResult` with the current `terminal_session_id`, `state == completed`, `exit_code == 0`. Return only IDs/tool names/status in receipts; do not copy outputs or credentials.
- [x] Persist accepted receipts under `session.metadata.completion_evidence` before successful completion. Existing sessions without the flag remain compatible.
- [x] Explain the active requirement and execution-ID parameter in the completion context. Explain that wrapper/tool executions can verify files, commits or test commands, but arbitrary prose/CLI claims do not create a receipt.
- [x] Run lifecycle, config-tool and context tests.

## Task 5 — Documentation, verification and review

- [x] Document full-read tools, paginated previews, recovery references, explicit blockers and opt-in receipts in operator guides and in-app mirrors.
- [x] Add changelog entries under `[Unreleased]` and index this plan.
- [x] Run focused suites and RuboCop on all changed Ruby files.
- [x] Run the full Docker gate with the local test-only GitHub key configuration: `docker compose exec -T web env GITHUB_APP_PRIVATE_KEY= PARALLEL_WORKERS=4 make check_all`.
- [x] Inspect every result, obtain independent code review, address findings, run `git diff --check`, and record evidence here. Do not push unless asked.

## Verification record

- Baseline on develop: 59 tests, 246 assertions, no failures/errors.
- Comment paging/full-read tests initially failed because the new tools were absent.
- Recovery tests reproduced lost tail constraints and incomplete structured-data previews; renderer regression reproduced compression cutting JSON.
- Required-evidence and config tests failed before implementation; a success note could not serve as the future receipt contract.
- Focused combined verification: 145 tests, 677 assertions, no failures/errors.
- Independent review found a secondary-compression gap for short arrow-prefixed notes. A new regression failed before the fix; recovery references now accompany every present note/data preview. The follow-up review found no remaining actionable issues.
- Recovery/reference regression verification after the fix: 54 tests, 240 assertions, no failures/errors.
- RuboCop: 23 changed/new Ruby files, no offenses. `git diff --check` passes.
- Full Docker gate: 2,061 frontend tests and 9 system tests passed; ESLint, TypeScript, FSD, watcher tests, Vite build, worker boot, Zeitwerk, RuboCop and Brakeman passed. The backend run found one missing reference-documentation config entry, now corrected and passing its focused test.
- Final full backend rerun: 8,082 tests, 25,236 assertions, zero failures/errors/skips; line coverage 93.80%. Command: `docker compose exec -T web env GITHUB_APP_PRIVATE_KEY= PARALLEL_WORKERS=4 make rails-test`. Frontend and static checks were not repeated because subsequent changes only affected Ruby recovery references and the system-reference documentation. The initial `make check_all` exited nonzero for the corrected reference omission; the rerun verifies the final backend tree.
- The local GitHub inline key is cleared only for the test process, so tests use their disposable PEM fixtures; no credentials or local configuration are modified.
