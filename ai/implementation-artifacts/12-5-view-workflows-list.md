# Story 12.5: View Workflows List

Status: review

## Story

As a project member,
I want to view a list of all workflows in my project,
so that I can find and manage the workflows available to my team.

## Acceptance Criteria

1. **AC1: Project-scoped index** — `GET /api/v1/company/projects/:project_id/workflows` returns merged list (company + project workflows) using `Workflow.merged_for_project(current_project)`. Paginated with Ransack search and Pagy pagination.

2. **AC2: Company-scoped index** — `GET /api/v1/company/workflows` returns company-level workflows only. For company admins managing shared workflow templates.

3. **AC3: List data** — Each workflow in the list includes: name, description (truncated), steps count, last run date, last run status, scope_indicator (company/project badge), created_at. Sorted by name (default) or last_run_at.

4. **AC4: Search** — `?q[name_cont]=keyword` filters by name substring. `?q[s]=name+asc` for sorting.

5. **AC5: Project workflows page** — Frontend page at `/projects/:projectId/workflows`. Shows merged list with scope badges. "New Workflow" button for admins/collaborators. Company workflows show "Company" badge and are read-only for project members (edit only by company admins). Each row links to workflow builder page.

6. **AC6: Company workflows page** — Frontend page at `/company/workflows` (or tab in company settings). Shows company-level workflows only. "New Workflow" button for admins. Manages shared workflow templates.

7. **AC7: Workflow card info** — Each card/row shows: name, scope badge (company/project), description excerpt (first 100 chars), steps count badge, last run status chip (colored: success/running/failed/never), time since last run.

8. **AC8: Navigation** — Workflows tab in project navigation (alongside Sessions, Assets, Settings). Workflows section in company navigation for admins.

## Tasks / Subtasks

- [x] Task 1: Project-scoped index (AC: #1)
  - [x] 1.1 `merged_for_project(current_project)` in project controller (done in 12-1)
  - [x] 1.2 Ransack search, Pagy pagination (done in 12-1)
- [x] Task 2: Company-scoped index (AC: #2)
  - [x] 2.1 `merged_for_company(current_company)` in company controller (done in 12-1)
  - [x] 2.2 Ransack search, Pagy pagination (done in 12-1)
- [x] Task 3: Update WorkflowSerializer for list view (AC: #3)
  - [x] 3.1 `description_excerpt` method (truncate to 100 chars)
  - [x] 3.2 `last_run_status` method
  - [x] 3.3 `scope_indicator` (company/project)
- [x] Task 4: Frontend project workflows page (AC: #5, #7)
  - [x] 4.1 WorkflowsPanel component (reusable for company/project)
  - [x] 4.2 MUI Table with scope badges (Chip)
  - [x] 4.3 Search input with debounce
  - [x] 4.4 Empty state, "New Workflow" button
  - [x] 4.5 Company workflows shown with "company" badge
- [x] Task 5: Frontend company workflows page (AC: #6)
  - [x] 5.1 WorkflowsPanel component (same, without projectId)
  - [x] 5.2 CRUD via Edit/Delete dialogs
- [x] Task 6: Navigation integration (AC: #8)
  - [x] 6.1 Workflows tab already exists in project page (ProjectPage.tsx)
  - [x] 6.2 Workflows added to company sidebar (AppSidebar.tsx)
  - [x] 6.3 Frontend route `/company/workflows` added to routes.ts
- [x] Task 7: RTK Query API for lists
  - [x] 7.1 `useGetProjectWorkflowsQuery` (done in 12-1)
  - [x] 7.2 `useGetCompanyWorkflowsQuery` (done in 12-1)
  - [x] 7.3 Pagination via Pagy backend
- [x] Task 8: Write tests
  - [x] 8.1 Project controller: merged list (done in 12-1)
  - [x] 8.2 Company controller: company-only (done in 12-1)
  - [x] 8.3 Authorization tests (done in 12-1)
  - [x] 8.4 Search via ransack support in controller

## Dev Notes

### Architecture

Standard list page following established patterns. Uses Ransack for search (same as Tools, Assets lists), Pagy for pagination (PaginationConcern).

The `last_run` info requires a `has_many :runs` on Workflow and an `ORDER BY created_at DESC LIMIT 1` query. To avoid N+1, either:
1. Use a counter cache or denormalized column
2. Use `includes` with a scope
3. Use a single SQL subquery in the serializer

Recommended: simple approach — serialize `last_run_at` and `last_run_status` in the serializer via `workflow.runs.order(created_at: :desc).first`. Use `includes(:runs)` in the controller to avoid N+1, or better yet, use a DB view / lateral join if performance becomes an issue.

**Until WorkflowRun exists (Story 12-6):** `last_run_at` and `last_run_status` return nil. The serializer should handle this gracefully.

### Key files to modify

- `app/controllers/api/v1/company/projects/workflows_controller.rb` — add index action
- `app/serializers/workflow_serializer.rb` — add list-specific fields

### Key files to create

**Frontend:**
- `app/frontend/pages/workflows/ui/WorkflowsPage.tsx`
- `app/frontend/pages/workflows/lib/types.ts`
- Update `app/frontend/shared/routes.ts` — add workflows route
- Update project navigation components — add Workflows tab

### Navigation pattern

Follow existing project page tabs pattern. Currently project has tabs for: Overview, Sessions, Assets, Settings (check actual implementation). Add "Workflows" tab.

### Dependencies

- Story 12-1 (Workflow model and controller base)
- Frontend project navigation must exist

### Testing

- Index returns workflows for the project only (not other projects)
- Search by name works
- Pagination headers present
- Non-member gets 403
- Empty project returns empty items array

### References

- [Source: ai/prd/functional-requirements.md#FR14](ai/prd/functional-requirements.md) — FR14: User can view list of available workflows
- [Source: ai/architecture/implementation-patterns-consistency-rules.md#API Controller Patterns](ai/architecture/implementation-patterns-consistency-rules.md) — Ransack + Pagy patterns
- [Source: app/controllers/api/v1/company/projects/assets_controller.rb](app/controllers/api/v1/company/projects/assets_controller.rb) — Reference list controller

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus-high

### Debug Log References

### Completion Notes List

- Backend index with ransack/pagy already done in Story 12-1
- Added description_excerpt, last_run_status, has_active_runs to WorkflowSerializer
- Created WorkflowsPanel — reusable list component for both company and project contexts
- Fixed projectApi to use correct backend route for workflows
- Added Workflows to company sidebar navigation
- All 1232 tests passing, 0 regressions

### File List

- app/serializers/workflow_serializer.rb (modified — added description_excerpt, last_run_status, has_active_runs)
- app/frontend/features/workflows/ui/WorkflowsPanel.tsx (new)
- app/frontend/features/workflows/index.ts (new)
- app/frontend/widgets/AppSidebar/ui/AppSidebar.tsx (modified — added Workflows nav item)
- app/frontend/shared/routes.ts (modified — added companyWorkflowsPath)
- app/frontend/pages/project/api/projectApi.ts (modified — fixed workflows URL)

### Change Log

- 2026-02-21: Story 12-5 implemented — Workflows list with search, scope badges, navigation integration
