# Token-efficient session context implementation plan (2026-10-12)

> **For agentic workers:** Execute inline, task by task, using the test-first and verification workflows. The user requested both planning and implementation in the current session.

**Goal:** Reduce irrelevant session context and make its remaining cost observable while preserving specifications and execution rules.

**Architecture:** Keep the existing BMAD integration and file-based artifact handoff. Scope previous-step summaries to the dependency graph, make the existing soft-budget compression observable, and teach the builder to choose a proportional spec-first workflow and narrowly scoped resources. Evaluate optional cross-run project memory through an isolated Engram pilot after establishing the baseline.

**Tech Stack:** Rails, Minitest, existing ContextBuilders and ContextRenderer; Docker for all application commands.

**Spec:** The contract below is the design for this bounded change, approved in the conversation through the request to plan and implement the proposed improvements.

## Contract and global constraints

- Previous-step summaries include completed/skipped transitive dependencies only, with the latest successful/skipped attempt per dependency. Independent branches and earlier attempts do not enter the initial context.
- Input/output file mounting, required-artifact validation, approval gates and BMAD installation remain compatible. Specifications stay available as files; do not truncate their contents to meet a prompt budget.
- The context budget is soft. Preserve critical instructions, resource paths and ordinary previous-step notes. Compress the existing optional sub-step data summaries and long arrow notes only; report when the final context still exceeds the budget.
- Estimates count the final XML wrappers and separators and use the existing four-characters-per-token heuristic, rounded up. These are context-file estimates, not provider usage or total session tokens.
- Keep existing metadata fields and add original/final rendered character counts, original/final token estimates, budget, exceeded flag and compressed section tags. Persist no new prompt contents in metadata.
- Builder guidance uses one canonical spec, proportional planning, explicit resources and no duplicate review without a distinct purpose. Existing workflows and resource assignments are not rewritten automatically.
- All Rails and dependency-dependent commands run inside Docker. Never run overlapping database-backed backend test invocations. No deployment or push is part of this task.
- RTK is explicitly excluded from this branch and plan at the user's request. Do not install it, add command-rewriting hooks or change agent images for it.

## Task 1: Dependency-scoped history

**Files:** `app/services/context_builders/workflow_context.rb`, `test/services/context_builders/workflow_context_test.rb`.

- [x] Add graph-based tests covering a transitive ancestor, an unrelated completed branch, no dependencies, and multiple completed attempts of the same dependency. Update history test setup to express the dependency it relies on.
- [x] Run the tests and observe failures on the unrelated history and stale attempts.
- [x] Filter completed runs with `where(step_id: step.upstream_step_ids)` and select the latest qualifying run per dependency, retaining deterministic position order and real collaborators.
- [x] Run the workflow-context regression tests; verify upstream asset listings still include transitive files and choose the nearest writer.

## Task 2: Render accounting and budget compression

**Files:** `app/services/context_renderer.rb`, `app/services/context_result.rb`, `test/services/context_renderer_test.rb`, `test/services/context_result_test.rb`, `test/services/session_context_service_test.rb`.

- [x] Add tests that estimate the complete rendered string, observe actual previous-step compression, retain critical/resource/spec sections and flag an uncompressible over-budget context.
- [x] Verify metadata corresponds to the exact injected file after compression, not just the original sections.
- [x] Run the new tests before implementation and confirm behavior failures.
- [x] Introduce a render report shared by `ContextRenderer.render` and `ContextResult`: render once, retain the old return type, and compare original/final sections for compression tags. Round up `(text.length.to_f / 4).ceil`.
- [x] Fix the existing previous-step compressor's data-line branch ordering. Remove ineffective skills/repository compressors rather than shortening paths or skill content. Preserve all critical sections even when the soft budget cannot be met.
- [x] Add the report's numeric metadata to `ContextResult#to_json_hash`; test persistence through the real context injection boundary.
- [x] Run renderer, result, constructor and context-service tests.

## Task 3: Proportional SDD and tool guidance

**Files:** `app/services/context_builders/output_rules.rb`, `app/services/context_builders/aixle_builder.rb`, their existing tests.

- [x] Change tool instructions to use only the MCP servers/tools needed for the task.
- [x] Add concise builder guidance: small changes need a mini-spec and tests; medium changes use canonical spec -> build/tests -> review; large/risky changes add architecture or specialized review. Pass paths to existing specs, attach only needed resources, and account for BMAD's built-in review before adding another.
- [x] Verify the complete builder context remains below its existing 28,000-byte compatibility bound and all named tools belong to its actual toolset.

## Task 4: Documentation, review and evidence

**Files:** `docs/user-guide/token-efficient-workflows.md`, `docs/user-guide/workflows.md`, `docs/reference/configuration.md`, `docs/index.md`, `CHANGELOG.md`.

- [x] Document configuration, the metadata schema, workflow patterns and a measurement protocol using comparable task cohorts, retries, quality outcomes, cache breakdown and Kiro credit caveats.
- [x] Add discoverable links and a user-visible changelog entry. Do not claim measured production savings.
- [x] Run focused regressions and RuboCop for changed Ruby files; review the diff independently.
- [x] Run `docker compose exec -T web make check_all` if the environment can provision the full test stack. Record any failures or environmental limitations explicitly.
- [x] Deliver changed paths, verified test results and remaining measurement work. Keep changes uncommitted for review unless the user asks otherwise.

## Task 5: Optional Engram cross-run memory pilot — implemented, evaluation pending

**Status:** Implemented at the user's request as an optional pilot, disabled by default for every project. Engram v3.4.0 runs in a private Docker service with persistent storage. Flow owns authorization, immutable findings, explicit human validation, source checks, quotas and retrieval snapshots; Engram supplies the search index. See the [operating guide](../user-guide/project-memory.md). Comparative savings and expansion remain pending.

**Purpose:** Avoid repeating investigations across separate workflow runs. BMAD continues to organize execution, SDD specifications define acceptance, workflow artifacts carry step outputs, and memory records validated discoveries and decisions. The current versioned specification and repository take precedence over conflicting memories.

**Recommendation:** Start with one explicitly enabled project and a pinned Engram release. Evaluate the existing engine before building a custom memory subsystem or adopting cloud synchronization. Engram provides SQLite/FTS5 storage and stdio MCP; its HTTP REST API is not itself a remote MCP endpoint.

### Benefits and tradeoffs

| Aspect | Potential benefit | Cost or limitation |
| --- | --- | --- |
| Cross-run continuity | Reuse known fixes, decisions and project conventions. | Incorrect or stale memories can repeat mistakes. |
| Token use | Targeted retrieval may replace repeated exploration and large file reads. | Tool definitions, searches, retrieved text and summaries also consume tokens. Savings require measurement. |
| Search | SQLite FTS5 supports retrieval without an embedding service. | Lexical search needs useful keywords and a shared language convention; cross-language equivalence is not automatic. |
| Integration | Flow exposes three narrow internal MCP tools backed by Engram HTTP. | A private persistent service and an application-owned authorization boundary require maintenance. |
| Knowledge maintenance | Stable topic keys update evolving knowledge. | Duplicate specifications, conflicting updates and expired facts need lifecycle rules. |
| Sharing | Optional synchronization can share project knowledge. | `personal` scope is a filter, not a privacy boundary; project synchronization can export personal observations too. |

### Required mitigations and acceptance criteria

The pilot must implement these controls before expansion. They reduce disadvantages; they do not guarantee perfect retrieval, zero maintenance or token savings. These are Flow requirements, not claims about Engram's built-in capabilities. Automated coverage and operational checks do not establish perfect retrieval or measured savings.

| Risk | Required control | Acceptance evidence |
| --- | --- | --- |
| Stale information | Store source paths, repository revision, validation date and review date. Compare source revisions before reuse; changed sources mark the memory as needing review. A different branch/revision alone does not prove a fact is false. | A changed source cannot silently retain validated status; the agent rechecks the current repository before relying on it. |
| Persistent mistakes | Use explicit `pending`, `validated` and `obsolete` states. Capture evidence from tests or review before marking a conclusion validated. Keep hypotheses pending and exclude them from default retrieval. | An unsupported hypothesis is not presented as a validated fact; corrections supersede prior conclusions without hiding provenance. |
| Duplicate or conflicting information | Store a brief finding and references rather than copies of specifications. Use stable topic keys for evolving facts and detect conflicting updates. Current specifications and code remain authoritative; unresolved conflicts trigger review. | Retrieval identifies the canonical source; conflicting updates cannot silently overwrite an accepted decision. |
| Token and latency overhead | Make memory opt-in per project. Configure per-session search-call, result-count and retrieved-token budgets plus response-size and request-time limits. Start with previews; fetch detail only when relevant. Stop optional retrieval when its budget is exhausted. | Oversized results and repeated searches stay bounded. Measurements include tool schemas, retrieval, capture and retries as well as ordinary task work. |
| Missed or irrelevant retrieval | Adopt shared terminology, topic keys, tags and a common language for shared memory. Retrieve only relevant validated records; low-confidence results fall back to repository investigation. | Representative queries are reviewed for relevance and missed useful records; absence of results is not treated as proof that no prior decision exists. |
| Cross-company/project access | Derive ownership from the authenticated Flow session and authorize every read/write, detail lookup, timeline, update, export and delete. Prevent global search and caller-controlled namespace changes. Apply isolation to storage and backups too. | Cross-tenant and cross-project denial tests cover guessed observation IDs, altered selectors and administrative paths, not just filtered search. |
| Operational complexity | Persist outside disposable containers, pin versions, test backup/restore and concurrent updates, and set retention/cleanup rules. Bound service failures with timeouts; ordinary workflows continue while failed reads/writes are recorded accurately. | Container replacement retains intended memory; restore and concurrency tests pass; outage tests show bounded delay and no false claim of successful capture. |
| Reduced reproducibility | Record the observation IDs, exact revisions and bounded retrieved snapshots used by each run in an authorized run manifest. Do not rely on mutable IDs alone. Support memory-disabled execution and replay from the recorded references/snapshots within retention limits. | Updating a memory does not erase the evidence of what an earlier run received. Access and deletion policies also cover stored snapshots. |
| Sensitive-data exposure | Exclude secrets, raw logs and transcript dumps. Explicitly configure capture behavior; keep git/cloud synchronization disabled during the pilot. Define authorized destinations and content policy before any sharing. | Capture tests reject representative sensitive payloads; no synchronization occurs by default, regardless of `personal` scope. |
| Retrieved instructions influencing execution | Treat retrieved memory as untrusted reference data, never as authority to change permissions, invoke tools or override execution rules. | Adversarial memory fixtures cannot expand access or bypass the specification and approval boundaries. |

**Minimum observation contract:** concise finding, topic/type/tags and language, company/project ownership, source paths and repository revision, originating session/run, validation evidence, state, validation/review dates, and immutable revision/provenance. Specify which fields are stored by Engram and which Flow must maintain before choosing the integration. Lifecycle and authorization checks must be enforced by trusted code rather than prompt instructions alone.

### Pilot implementation sequence

- [x] Define a small pilot specification: one project, supported agent adapters, retrieval/capture limits, failure behavior and acceptance criteria. Pin a released version and verify its actual contracts rather than assuming every feature on `main` is available.
- [x] Map every required mitigation above to Engram capabilities or a Flow-owned control. Set concrete budget values, retention periods and acceptable outcome thresholds before running the comparison. Keep the first pilot limited to bounded retrieval and explicitly saved validated findings; broader automation and synchronization follow only after evidence supports them.
- [ ] Establish a baseline using the existing context optimizations with memory disabled. Select 20–30 comparable tasks covering recurring bugs, repository conventions and architectural decisions; document the sample's limits.
- [x] Implement private REST storage in a dedicated Docker volume, scoped internal MCP tools and asynchronous projection cleanup. Serialize writes and session quotas with database locks; verify container replacement retains indexed findings.
- [x] Restore a consistent Engram SQLite backup into an isolated volume and verify search/write/delete without affecting the original index.
- [x] Exercise threaded database connections for retrieval/capture quotas and competing administrative reviews; observe both workers waiting on a database lock.
- [x] Rehearse paired PostgreSQL/index recovery against isolated restored data.
- [ ] Exercise sustained production-like load before expanding the pilot.
- [x] Enforce company/project authorization in trusted Flow code. Derive the namespace from the authenticated session; do not rely on agent-supplied project names or Engram scope filters for tenant isolation. Keep cloud/git synchronization disabled initially.
- [x] Add an explicit project-level opt-in and bounded on-demand retrieval: compact search results first, full observations only when relevant. Do not inject the entire memory store into every initial prompt. Keep the selected tools narrow.
- [x] Capture concise, validated discoveries after successful work, with source paths, repository revision, session/run provenance and review date. Use stable topic keys where knowledge evolves. Exclude credentials, raw logs and transcript dumps; configure prompt capture explicitly for the chosen integration.
- [x] Define review, correction and deletion behavior for stale or conflicting memories. Treat retrieved content as reference data; it must not override execution rules or the current specification.
- [x] Test cross-project/tenant denials, viewer and revoked access, source changes, conflicting proposals, retrieval limits, disabled mode, service outages and container replacement. Memory failures return explicit bounded errors.
- [ ] Exercise sustained concurrent writes and recovery under production-like load.
- [x] Verify source-change invalidation, pending/obsolete exclusion, conflicting updates, representative secret rejection, immutable provenance, exact retrieval snapshots and local deletion during outages.
- [ ] Evaluate adversarial instruction content with actual agent runs and rehearse retention/restore procedures. Reference-only guidance cannot prove an LLM will ignore all hostile instructions.
- [ ] Measure total provider tokens and cost per accepted task, cache effects, retries, latency, exploration tool calls and memory relevance. Include memory writes and retrieval in the totals; rendered-context estimates alone cannot establish savings.
- [ ] Review the results before expanding: require no observed isolation failures, no degradation in acceptance/rework outcomes, and a documented net cost or completion-time benefit. If results are inconclusive, extend the sample; if unfavorable, leave memory disabled and retain the existing context improvements.

**Residual risks and rollout decision:** Search can still miss relevant facts, validation can still be wrong, and memory maintenance adds work. A 20–30-task pilot provides preliminary evidence, not a universal savings estimate or proof of isolation. Security controls require dedicated verification independent of task outcomes. Expand only after the mitigation checks pass and measured benefits justify ongoing operation; retain the opt-out and memory-disabled fallback after rollout.

**Evidence sources reviewed:** [Engram repository](https://github.com/Gentleman-Programming/engram), [architecture and retrieval](https://github.com/Gentleman-Programming/engram/blob/main/docs/ARCHITECTURE.md), [MCP and HTTP contracts](https://github.com/Gentleman-Programming/engram/blob/main/DOCS.md), [team scope and synchronization limits](https://github.com/Gentleman-Programming/engram/blob/main/docs/TEAM-USAGE.md), and [released versions](https://github.com/Gentleman-Programming/engram/releases). Revalidate these moving references when implementing the pilot.

## Verification and develop review (Tasks 1–4)

- Focused context regressions: 162 runs, 563 assertions, no failures, errors or skips. The new behavior failed before implementation.
- Full `make check_all`: all 12 checks passed. Backend: 8,041 tests and 25,043 assertions; frontend: 2,058 tests across 180 files; system: 9 tests and 51 assertions. Line coverage: backend 93.80%, frontend 85.16%.
- Independent code review found no actionable issues. Actual provider-token savings and cost per accepted task remain to be measured; rendered-context estimates are not billing usage.
- Fetched `origin/develop` after implementation: local `56d1bacc` is behind `518114f2` (`chore(release): 1.2.1 (#474)`) by one commit. That commit changes only `CHANGELOG.md`, adding the 1.2.1 release heading and comparison links. No application-code overlap was found. On integration, retain this change's new entries under `Unreleased`, outside the released 1.2.1 section. No merge, commit, push or deployment was performed.

## Implemented pilot boundaries

- Project owners and company administrators explicitly opt in; viewers cannot capture, review or enable memory. Captures remain pending until an authorized reviewer validates evidence and current GitHub source revisions. GitLab/Azure sources fail closed during this pilot.
- Per session: five retrieval calls, three results per search, 200-character previews, 1,800-character details, 2,000 estimated retrieved tokens including metadata, and ten capture proposals. Each external request has a deadline and response-size cap. Estimates are not provider billing.
- Versioned canonical findings and run manifests live in PostgreSQL. Revision-specific indexed content prevents Engram's content deduplication from reusing a prior version's index ID. Pending, obsolete and expired findings are excluded. Cleanup jobs retry scoped index deletion without blocking local deletion or ordinary workflows.
- Synchronization and prompt capture are disabled; storage is private to the application network. Retention commands cover snapshots older than 30 days and pending/obsolete findings older than 90 days; operators must schedule and rehearse them.
- A recorded manifest preserves exact retrieved payloads within retention limits; automatic agent replay is not implemented. No empirical savings claim or automatic rollout is made.

## Pilot verification and branch status (2026-10-12)

- Work is on `feat/token-efficiency-engram`, created from local `develop` without discarding the earlier context changes. No commit, push or remote deployment has been performed.
- Full Docker `make check_all`: all 12 checks passed; 8,087 backend tests / 25,192 assertions, 2,062 frontend tests / 180 files, and 9 system tests. Full-run line coverage: backend 93.81%, frontend 85.15%.
- After that full run, review identified Engram's cross-topic content deduplication. The regression reproduces a duplicate index-ID constraint violation without the revision-specific header. With the correction, all 50 memory-focused tests / 187 assertions pass, and RuboCop reports no offenses in the three final changed files. A second independent review found no remaining issue in this correction.
- Real Engram 3.4.0 checks verified save/search, persistence across container replacement, idempotent scoped deletion, separate IDs for identical findings with distinct revision headers, and preservation of the new revision after deleting the old projection. Smoke observations were deleted.
- The local web container was recreated with the optional Engram overlay. Both services report healthy, and the application confirms memory is configured. No project was automatically opted in; the owner/admin switch remains the activation boundary.
- Fetched `origin/develop` again after implementation. It remains one commit ahead: `518114f2 chore(release): 1.2.1 (#474)`, changing only the release heading/comparison links in `CHANGELOG.md`. No application-code overlap; preserve new entries under `Unreleased` when integrating. No merge was performed.
- Comparative token/cost measurements, production-like concurrency stress and actual-agent adversarial evaluation remain pre-expansion work; no net savings or zero-risk claim is made.

## Additional recovery and concurrency checks (2026-10-12)

- `ProjectMemoryConcurrencyTest` uses committed fixtures and two independent PostgreSQL connections. It holds the project lock until both worker PIDs report lock waits; this verifies actual contention rather than relying on thread scheduling. Quota calls share a session, while review calls use independent administrative services without a session lock.
- Verified five successful retrievals / five quota denials, ten captures / six quota denials, and exactly one accepted review / one revision conflict. Worker execution has a deadline and cancellation before fixture cleanup.
- Stopped only Engram, archived the SQLite database and available WAL/SHM files plus instance identity, restored into a new volume, and restarted the original service. The restored instance retained the known finding and supported new writes and scoped deletion while the original volume remained unchanged.
- Removed temporary probe observations, the restored container/volume and the temporary backup archive. This is an Engram index recovery exercise, not a full PostgreSQL/application recovery or a production-load benchmark.

- Final focused regression after the concurrency helper refinements: `bin/rails test test/services/project_memory_concurrency_test.rb test/services/project_memory_service_test.rb test/integration/project_memory_mcp_test.rb` in Docker passed 27 tests / 129 assertions (seed 29348), no failures/errors/skips. RuboCop passed for the new test file. Independent review found no remaining issue in the concurrency tests.
- Original Flow and Engram containers both reported healthy after recovery cleanup. No project opt-in, commit, push or merge was performed.

## Task 6: Measurement export — implemented

Provide an owner/admin-only JSON export for an explicit selection of at most 100 sessions in one project. Reject foreign, mismatched-tenant and missing selectors as a whole. Include reported provider usage, source/model/cache breakdown, timing and memory counters; exclude prompts, findings and raw usage events. Missing usage stays null, and zero/credit-only token counts do not count as a usable token measurement. Cohort/accepted-task/retry labels are assigned explicitly by the operator; never infer historical memory activation from the project's current switch. No automatic provider runs or savings claim.

## Paired recovery evidence and measurement preparation (2026-10-12)

- Created a controlled project/session/repository/finding in the test database, validated/indexed it through the real Engram adapter, and took a PostgreSQL custom-format dump plus a stopped-service SQLite archive. No development database backup or real project opt-in was involved. Source freshness was supplied by the deterministic test verifier; this exercise validates recovery, not GitHub availability.
- Restored PostgreSQL to a separate `aixle_memory_recovery` database and SQLite to a separate volume/container. Verified the original Flow finding ID, immutable UUID and Engram ID association, index search resolving the canonical record, exact retrieval payload snapshots, denial of foreign-project detail access, and removal of the restored finding/snapshots without changing the original index.
- Removed the temporary source fixtures/index observation, restored database/container/volume, PostgreSQL dump and SQLite archive.
- Task 6 implementation adds `ProjectMemoryMetrics` and `project_memory:metrics`. It exports selected authorized session statistics separately from memory estimates, leaves missing usage null, does not infer historical cohort activation, and omits raw events, prompts and finding bodies. Zero/default precise-cost values are withheld rather than presented as exact zero charges.
- Actual 20–30-task cohort selection and provider runs remain pending. No synthetic fixture result is presented as observed token/cost savings.

- Measurement tests failed before implementation; a separate regression caught the default precise-cost zero being exported as an exact charge and passed after suppressing unavailable precision. Final focused coverage: 68 tests / 259 assertions (seed 60387), no failures/errors/skips, including metrics authorization/privacy, memory domain, concurrent connections, MCP/settings, adapter/source verification, cleanup and changelog checks. RuboCop passed for the three measurement files.
- A real Rails maintenance-task smoke invoked `project_memory:metrics` with an authorized baseline session, parsed its JSON output, verified null usage/cohort, and rolled back its fixtures. The export uses existing database statistics; it does not invoke an agent/model or the Engram service. Independent scoped review found no concrete authorization or data-semantic issues.
- Requested the pilot project name/ID from the user before selecting a real cohort. No project was automatically enabled and no paid agent tasks were launched.

## Final combined verification and scope (2026-10-12)

- Re-ran Docker `make check_all` after the revision-index correction, concurrency tests and measurement export. All 12 checks passed: 8,097 backend tests / 25,235 assertions, 2,062 frontend tests across 180 files, and 9 system tests / 51 assertions. Line coverage: backend 93.81%, frontend 85.15%.
- Fetched `origin/develop` again: it remains one commit ahead (`518114f2`, release 1.2.1), with changes only to `CHANGELOG.md`. No merge was performed; new entries must remain under `Unreleased` when integrating.
- RTK is excluded at the user's explicit request. No RTK binary, agent hook, image change or runtime configuration was added.
- The implementation remains on `feat/token-efficiency-engram`, uncommitted and unpushed. Project selection, actual provider-cost comparison, sustained load and actual-agent adversarial evaluation remain pending; the pilot is not automatically enabled for any project.

## Develop integration (2026-10-12)

- At the user's request, integrated freshly fetched `origin/develop` into `feat/token-efficiency-engram` by fast-forward to `518114f2`. The feature changes remain uncommitted; no push was performed.
- Temporarily saved only the overlapping changelog edits, restored them after integration and resolved the release-heading conflict. Feature entries remain under `Unreleased`; the existing release entries remain under 1.2.1. All other local changes were preserved.
- Verified `origin/develop` is an ancestor of `HEAD`, no unresolved paths remain, and `git diff --check` passes. Docker changelog regression: 12 tests / 69 assertions, no failures/errors/skips. The incoming commit changes only the changelog; application code is unchanged from the preceding full-suite verification.

## Pre-push review and lifecycle correction (2026-10-12)

- The user authorized committing and pushing the feature branch to their fork. The original project's pull request remains a proposed title/description, not an automatically submitted contribution.
- Final packaging review found that the proxy could outlive a failed Engram process, preventing Compose's restart policy from recovering the service. Added a supervisor that terminates/reaps both children and reports unexpected exits as failures. The original image failed the disposable-container regression; the corrected image passes startup failure, Engram failure, proxy failure and graceful shutdown. Independent review found no remaining lifecycle issue; the recreated local service reports healthy.
- The first pre-push full run passed all 2,062 frontend tests but failed on an unhandled Mantine transition timer after jsdom teardown in the existing `SessionNewForm` tests. That file passed all 24 tests in isolation. No shared-helper change was made without a reproducible cause.
- A subsequent run encountered 3 failures and 25 errors in GitHub tests because a locally configured inline private key took precedence over their temporary test key files. That failed run was stopped after backend completion. The next full run isolates only `GITHUB_APP_PRIVATE_KEY` to an empty value at command scope; the local `.env` and development database remain unchanged.
- Final pre-push gate: `docker compose exec -T -e GITHUB_APP_PRIVATE_KEY= web make check_all` passed all 12 checks: 8,097 backend tests / 25,237 assertions, 2,062 frontend tests across 180 files, and 9 system tests / 51 assertions. Line coverage: backend 93.81%, frontend 85.15%. The intermittent Mantine error did not recur in this full run; it is not claimed fixed. The four separate container lifecycle checks also passed.
