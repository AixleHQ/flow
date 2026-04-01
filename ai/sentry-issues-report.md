# Sentry Issues Report

**Date:** 2026-03-27
**Organization:** aixle
**Total unresolved issues:** 18

---

## Summary by Project

| Project | Issues | Total Events | Top Problem |
|---------|--------|-------------|-------------|
| aixle-rails | 10 | 1,626 | N+1 Queries (7 issues, 1,562 events) |
| aixle-temporal | 6 | 14 | Container phase failures |
| aixle-frontend | 2 | 3 | TypeError |

---

## CRITICAL: Most Frequent Issues

### 1. N+1 Query in TasksController#index — 1,492 events
- **ID:** [PALAD-AI-RAILS-S](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-S)
- **Project:** aixle-rails
- **Culprit:** `Api::V1::Company::Projects::Board::TasksController#index`
- **Users affected:** 2
- **First seen:** 2026-03-23 | **Last seen:** 2026-03-26
- **Actionability:** medium
- **Notes:** By far the most frequent issue. N+1 query on the board tasks listing endpoint. Likely missing `includes`/`preload` on associations.

### 2. PG::UndefinedTable "task_waits" in TasksController#show — 51 events
- **ID:** [PALAD-AI-RAILS-Q](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-Q)
- **Project:** aixle-rails
- **Culprit:** `Api::V1::Company::Projects::Board::TasksController#show`
- **Users affected:** 1
- **First seen:** 2026-03-23 | **Last seen:** 2026-03-23
- **Actionability:** medium
- **Notes:** Table `task_waits` does not exist. Either a missing migration or a reference to a removed/renamed table.

### 3. N+1 Query in WorkflowRunsController#index — 34 events
- **ID:** [PALAD-AI-RAILS-V](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-V)
- **Project:** aixle-rails
- **Culprit:** `Api::V1::Company::Projects::WorkflowRunsController#index`
- **Users affected:** 1
- **First seen:** 2026-03-26 | **Last seen:** 2026-03-27
- **Notes:** New N+1 query in workflow runs listing.

---

## All Issues by Project

### aixle-rails (10 issues)

| # | ID | Title | Events | Users | Culprit | Actionability |
|---|-----|-------|--------|-------|---------|---------------|
| 1 | [RAILS-S](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-S) | N+1 Query | 1,492 | 2 | `Board::TasksController#index` | medium |
| 2 | [RAILS-Q](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-Q) | PG::UndefinedTable: "task_waits" does not exist | 51 | 1 | `Board::TasksController#show` | medium |
| 3 | [RAILS-V](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-V) | N+1 Query | 34 | 1 | `WorkflowRunsController#index` | — |
| 4 | [RAILS-P](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-P) | N+1 Query | 13 | 2 | `WorkflowRunsController#index` | medium |
| 5 | [RAILS-R](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-R) | PG::UndefinedTable: "task_waits" does not exist | 12 | 1 | `Board::TasksController#index` | medium |
| 6 | [RAILS-H](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-H) | N+1 Query | 12 | 2 | `ProjectsController#index` | medium |
| 7 | [RAILS-W](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-W) | N+1 Query | 9 | 1 | `WorkflowRunsController#index` | — |
| 8 | [RAILS-X](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-X) | N+1 Query | 1 | 1 | `WorkflowsController#index` | — |
| 9 | [RAILS-T](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-T) | N+1 Query | 1 | 1 | `Board::TasksController#workflow_runs` | — |
| 10 | [RAILS-3](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-3) | Github::TokenService::AuthenticationError (404) | 1 | 1 | `RepositoriesController#available` | low |

### aixle-temporal (6 issues)

| # | ID | Title | Events | Culprit | Actionability |
|---|-----|-------|--------|---------|---------------|
| 1 | [TEMPORAL-4](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-4) | Pod failed to start within 60s | 4 | `PhaseActivity in run` | super_low |
| 2 | [TEMPORAL-2](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-2) | Exceeded quota: memory 6Gi/8Gi, requested 3Gi | 4 | `PhaseActivity in run` | super_low |
| 3 | [TEMPORAL-D](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-D) | Phase start_container: Activity canceled | 3 | `PhaseActivity in run` | — |
| 4 | [TEMPORAL-E](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-E) | Activity canceled | 1 | `UpdateWorkflowRunStatusActivity` | — |
| 5 | [TEMPORAL-C](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-C) | Activity canceled | 1 | `WorkflowRunStateMachine in on_completed` | low |
| 6 | [TEMPORAL-B](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-B) | Phase create_container: Unauthorized | 1 | `PhaseActivity in run` | low |

### aixle-frontend (2 issues)

| # | ID | Title | Events | Users | Culprit | Actionability |
|---|-----|-------|--------|-------|---------|---------------|
| 1 | [FRONTEND-4](https://palad-ai.sentry.io/issues/PALAD-AI-FRONTEND-4) | TypeError: Cannot read properties of undefined (reading 'toLocaleString') | 2 | 2 | `/company/projects/1/overview` | medium |
| 2 | [FRONTEND-3](https://palad-ai.sentry.io/issues/PALAD-AI-FRONTEND-3) | TypeError: Failed to fetch dynamically imported module | 1 | 1 | `/company/settings` | low |

---

## Fixes Applied

### FIXED: N+1 Queries (7 issues, ~1,562 events)

| Issue | Fix | File |
|-------|-----|------|
| RAILS-S: TasksController#index (1,492 events) | Added `{ workflow_runs: :workflow }` to includes | `tasks_controller.rb:11` |
| RAILS-V/P/W: WorkflowRunsController#index (56 events) | Rewrote `current_step_info` to use preloaded step_runs instead of DB query; rewrote `past_failures` to filter in-memory; removed extra `.includes(:sub_step)` from sub_step_runs | `workflow_run_serializer.rb`, `step_run_serializer.rb` |
| RAILS-H: ProjectsController#index (12 events) | Added SQL subselect for `last_activity_at` to eliminate per-project query | `projects_controller.rb`, `project_serializer.rb` |
| RAILS-X: WorkflowsController#index (1 event) | Preloaded company_override_names in controller, passed to serializer; added `project:` option | `workflows_controller.rb`, `scope_indicator_serialization.rb` |
| RAILS-T: TasksController#workflow_runs (1 event) | Added `.includes(:workflow)` to query | `tasks_controller.rb:56` |

### NOT CODE — Deployment/Config Issues

| Issue | Root Cause | Action Needed |
|-------|-----------|---------------|
| RAILS-Q/R: "task_waits" table missing (63 events) | Migration exists (`20260320200000_create_task_waits`), table in schema.rb — DB not migrated on target env | Run `rake db:migrate` on deployed environment |
| RAILS-3: GitHub token 404 (1 event) | Stale installation_id in encrypted credentials | Re-authenticate GitHub App integration |
| TEMPORAL-2: Memory quota exceeded (4 events) | K8s resource quota 8Gi hit | Increase quota or optimize pod memory |
| TEMPORAL-4: Pod start timeout (4 events) | Pod fails to start within 60s | Investigate slow image pulls / resource contention |
| TEMPORAL-B: Unauthorized container create (1 event) | Auth issue with container registry | Check registry credentials |
| TEMPORAL-C/D/E: Activity canceled (5 events) | User-initiated or timeout cancellations | Expected behavior, low priority |
| FRONTEND-3: Dynamic import failed (1 event) | Stale browser cache after deploy | Expected behavior, self-resolving |

### FIXED: Frontend TypeError (2 events)

| Issue | Fix | File |
|-------|-----|------|
| FRONTEND-4: toLocaleString on undefined | Added `?? 0` fallback for `sessionsLaunched`, `workflowsCount`, `boardTasksCount` | `ProjectOverviewPanel.tsx:252,262,267` |
