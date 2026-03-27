# Sentry Issues Report

**Date:** 2026-03-27
**Organization:** palad-ai
**Total unresolved issues:** 18

---

## Summary by Project

| Project | Issues | Total Events | Top Problem |
|---------|--------|-------------|-------------|
| palad-ai-rails | 10 | 1,626 | N+1 Queries (7 issues, 1,562 events) |
| palad-ai-temporal | 6 | 14 | Container phase failures |
| palad-ai-frontend | 2 | 3 | TypeError |

---

## CRITICAL: Most Frequent Issues

### 1. N+1 Query in TasksController#index — 1,492 events
- **ID:** [PALAD-AI-RAILS-S](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-S)
- **Project:** palad-ai-rails
- **Culprit:** `Api::V1::Company::Projects::Board::TasksController#index`
- **Users affected:** 2
- **First seen:** 2026-03-23 | **Last seen:** 2026-03-26
- **Actionability:** medium
- **Notes:** By far the most frequent issue. N+1 query on the board tasks listing endpoint. Likely missing `includes`/`preload` on associations.

### 2. PG::UndefinedTable "task_waits" in TasksController#show — 51 events
- **ID:** [PALAD-AI-RAILS-Q](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-Q)
- **Project:** palad-ai-rails
- **Culprit:** `Api::V1::Company::Projects::Board::TasksController#show`
- **Users affected:** 1
- **First seen:** 2026-03-23 | **Last seen:** 2026-03-23
- **Actionability:** medium
- **Notes:** Table `task_waits` does not exist. Either a missing migration or a reference to a removed/renamed table.

### 3. N+1 Query in WorkflowRunsController#index — 34 events
- **ID:** [PALAD-AI-RAILS-V](https://palad-ai.sentry.io/issues/PALAD-AI-RAILS-V)
- **Project:** palad-ai-rails
- **Culprit:** `Api::V1::Company::Projects::WorkflowRunsController#index`
- **Users affected:** 1
- **First seen:** 2026-03-26 | **Last seen:** 2026-03-27
- **Notes:** New N+1 query in workflow runs listing.

---

## All Issues by Project

### palad-ai-rails (10 issues)

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

### palad-ai-temporal (6 issues)

| # | ID | Title | Events | Culprit | Actionability |
|---|-----|-------|--------|---------|---------------|
| 1 | [TEMPORAL-4](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-4) | Pod failed to start within 60s | 4 | `PhaseActivity in run` | super_low |
| 2 | [TEMPORAL-2](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-2) | Exceeded quota: memory 6Gi/8Gi, requested 3Gi | 4 | `PhaseActivity in run` | super_low |
| 3 | [TEMPORAL-D](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-D) | Phase start_container: Activity canceled | 3 | `PhaseActivity in run` | — |
| 4 | [TEMPORAL-E](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-E) | Activity canceled | 1 | `UpdateWorkflowRunStatusActivity` | — |
| 5 | [TEMPORAL-C](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-C) | Activity canceled | 1 | `WorkflowRunStateMachine in on_completed` | low |
| 6 | [TEMPORAL-B](https://palad-ai.sentry.io/issues/PALAD-AI-TEMPORAL-B) | Phase create_container: Unauthorized | 1 | `PhaseActivity in run` | low |

### palad-ai-frontend (2 issues)

| # | ID | Title | Events | Users | Culprit | Actionability |
|---|-----|-------|--------|-------|---------|---------------|
| 1 | [FRONTEND-4](https://palad-ai.sentry.io/issues/PALAD-AI-FRONTEND-4) | TypeError: Cannot read properties of undefined (reading 'toLocaleString') | 2 | 2 | `/company/projects/1/overview` | medium |
| 2 | [FRONTEND-3](https://palad-ai.sentry.io/issues/PALAD-AI-FRONTEND-3) | TypeError: Failed to fetch dynamically imported module | 1 | 1 | `/company/settings` | low |

---

## Key Patterns & Recommendations

### 1. N+1 Queries (7 issues, ~1,562 events) — HIGH PRIORITY
The dominant problem. Affected controllers:
- `Board::TasksController#index` — 1,492 events (!!!)
- `WorkflowRunsController#index` — 3 separate N+1 issues (56 events combined)
- `ProjectsController#index` — 12 events
- `WorkflowsController#index` — 1 event
- `Board::TasksController#workflow_runs` — 1 event

**Fix:** Add proper `includes`/`preload` to ActiveRecord queries in these controllers/serializers.

### 2. Missing "task_waits" Table (2 issues, 63 events) — HIGH PRIORITY
Both `TasksController#show` and `TasksController#index` reference a `task_waits` table that doesn't exist. This is a hard error breaking task-related functionality.

**Fix:** Either create the missing migration or remove the reference to `task_waits`.

### 3. Container Resource Limits (2 issues, 8 events) — MEDIUM
Pods failing to start due to timeout (60s) or memory quota exceeded (8Gi limit hit).

**Fix:** Review resource quotas and pod startup times. Consider increasing limits or optimizing container startup.

### 4. Activity Cancellation (3 issues, 5 events) — LOW
Temporal activities being canceled during workflow execution. Likely caused by user-initiated cancellations or timeouts.

### 5. Frontend TypeError (1 issue, 2 events) — LOW
`toLocaleString` called on undefined in project overview page. Likely a missing null check on a numeric field.
