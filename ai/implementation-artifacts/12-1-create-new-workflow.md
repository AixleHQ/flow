# Story 12.1: Create New Workflow

Status: review

## Story

As a company admin or project member,
I want to create a new workflow at company or project level,
so that I can define reusable multi-step processes shared across projects or specific to one.

## Acceptance Criteria

1. **AC1: Workflow model with polymorphic scope** — `Workflow` model with polymorphic `scope` (Company | Project), following the same pattern as Agent, Tool, MCPServer, Skill, Asset, ConfigItem, Repository. Fields: `name` (string, required), `description` (text), `config` (jsonb), `scope_type` (string, NOT NULL), `scope_id` (integer, NOT NULL). Validates presence of name and scope. Unique name per scope (`[scope_type, scope_id, name]`).

2. **AC2: Migration** — Create `workflows` table with columns: `id`, `name`, `description`, `config` (jsonb, default: {}), `scope_type` (string, NOT NULL), `scope_id` (integer, NOT NULL), `created_at`, `updated_at`. Indexes: `[scope_type, scope_id]` and unique `[scope_type, scope_id, name]`.

3. **AC3: Merge pattern** — `Workflow.merged_for_project(project)` returns company-level + project-level workflows. Project workflows override company by name (same pattern as Agent/Tool). `Workflow.for_company(company)` returns company-level only.

4. **AC4: Company-scoped API** — `POST /api/v1/company/workflows` creates a company-level workflow. `GET /api/v1/company/workflows` lists company workflows. For admins only.

5. **AC5: Project-scoped API** — `POST /api/v1/company/projects/:project_id/workflows` creates a project-level workflow. `GET /api/v1/company/projects/:project_id/workflows` lists merged workflows (company + project). `GET .../workflows/:id` returns single workflow with steps count and last run info.

6. **AC6: Serializer** — `WorkflowSerializer` with attributes: `id`, `name`, `description`, `config`, `scope_type`, `scope_id`, `scope_indicator` (company/project badge), `steps_count`, `last_run_at`, `created_at`, `updated_at`.

7. **AC7: Authorization** — Two Pundit policies:
   - `Api::V1::Company::WorkflowsPolicy` — company admins can CRUD
   - `Api::V1::Company::Projects::WorkflowsPolicy` — project admins and collaborators can CRUD project workflows; all project members can read merged list

8. **AC8: Frontend form** — "New Workflow" dialog with scope selector (company vs project). Available on company workflows page and project workflows tab. Fields: name (required), description (optional). On success, redirects to workflow builder page.

9. **AC9: RTK Query API** — `workflowsApi` with endpoints for both company and project scopes: `useCreateWorkflowMutation`, `useGetWorkflowsQuery` (company/project), `useGetWorkflowQuery`.

## Tasks / Subtasks

- [x] Task 1: Create migration for `workflows` table (AC: #2)
  - [x] 1.1 Generate migration with scope_type, scope_id, all columns and indexes
  - [x] 1.2 Run migration, verify schema
- [x] Task 2: Create `Workflow` model (AC: #1, #3)
  - [x] 2.1 `belongs_to :scope, polymorphic: true` (Company | Project)
  - [x] 2.2 `has_many :steps, dependent: :destroy` (deferred — comment placeholder, added in Story 12-2)
  - [x] 2.3 `has_many :runs, class_name: 'WorkflowRun'` (deferred — comment placeholder, added in Story 12-6)
  - [x] 2.4 Validations: presence of name, uniqueness scoped to `[scope_type, scope_id]`
  - [x] 2.5 Scopes: `for_company(company)`, `for_project(project)`, `merged_for_project(project)`
  - [x] 2.6 Factory: `test/factories/workflows.rb` with traits `:with_company_scope`, `:with_project_scope`
- [x] Task 3: Create `WorkflowSerializer` (AC: #6)
  - [x] 3.1 Attributes: id, name, description, config, scope_type, scope_id, scope_indicator, steps_count, last_run_at, timestamps
  - [x] 3.2 `scope_indicator` method: "company" or "project"
- [x] Task 4: Create Company `WorkflowsController` (AC: #4)
  - [x] 4.1 `Api::V1::Company::WorkflowsController`
  - [x] 4.2 Actions: index, show, create, update, destroy
  - [x] 4.3 Scoped to `current_company.workflows` (via `scope_type: 'Company'`)
- [x] Task 5: Create Project `WorkflowsController` (AC: #5)
  - [x] 5.1 `Api::V1::Company::Projects::WorkflowsController`
  - [x] 5.2 `index` returns `Workflow.merged_for_project(current_project)`
  - [x] 5.3 `create` scopes to project
  - [x] 5.4 `show` finds in merged scope
- [x] Task 6: Create Pundit policies (AC: #7)
  - [x] 6.1 `Api::V1::Company::WorkflowsPolicy` — admin only
  - [x] 6.2 `Api::V1::Company::Projects::WorkflowsPolicy` — admin + collaborator CRUD, all members read
- [x] Task 7: Add routes (AC: #4, #5)
  - [x] 7.1 Company-level: `resources :workflows` under company namespace
  - [x] 7.2 Project-level: `resources :workflows` nested under projects
- [x] Task 8: Frontend RTK Query API (AC: #9)
  - [x] 8.1 `workflowsApi.ts` with company and project endpoints
  - [x] 8.2 Endpoints: createWorkflow, getWorkflows (company/project), getWorkflow
- [x] Task 9: Frontend "New Workflow" dialog (AC: #8)
  - [x] 9.1 `CreateWorkflowDialog` with RHF + Zod
  - [x] 9.2 Fields: name (required), description (optional)
  - [x] 9.3 Scope context from parent page (company page → company scope, project page → project scope)
  - [x] 9.4 On success callback for redirect to workflow builder
- [x] Task 10: Write tests
  - [x] 10.1 Model test: validations, associations, merged_for_project, scopes (14 tests)
  - [x] 10.2 Company controller test: CRUD, admin-only authorization (8 tests)
  - [x] 10.3 Project controller test: CRUD, merged list, authorization (7 tests)
  - [x] 10.4 Serializer test: scope_indicator (covered in model test)

## Dev Notes

### Architecture — Polymorphic Scope Decision

**Updated:** Workflow uses polymorphic `scope` (Company | Project), matching the established pattern for Agent, Tool, MCPServer, Skill, Asset, ConfigItem, Repository.

**Business rationale:** Company can define standard workflows ("Product Planning", "Code Report", "Security Audit") available in all projects. Projects can create project-specific workflows or override company ones by name.

**Key difference from original design:** workflow-architecture.md has `belongs_to :project`. We change to `belongs_to :scope, polymorphic: true`. WorkflowRun still belongs to Project (execution is always project-scoped).

**Merge pattern (same as Agent/Tool):**
```ruby
scope :for_company, ->(company) { where(scope_type: 'Company', scope_id: company.id) }
scope :for_project, ->(project) { where(scope_type: 'Project', scope_id: project.id) }

def self.merged_for_project(project)
  where(scope_type: 'Project', scope_id: project.id)
    .or(where(scope_type: 'Company', scope_id: project.company_id))
end
```

### Key files to create

**Backend:**
- `db/migrate/YYYYMMDDHHMMSS_create_workflows.rb`
- `app/models/workflow.rb`
- `app/serializers/workflow_serializer.rb`
- `app/controllers/api/v1/company/workflows_controller.rb`
- `app/controllers/api/v1/company/projects/workflows_controller.rb`
- `app/policies/api/v1/company/workflows_policy.rb`
- `app/policies/api/v1/company/projects/workflows_policy.rb`
- `test/factories/workflows.rb`
- `test/models/workflow_test.rb`
- `test/controllers/api/v1/company/workflows_controller_test.rb`
- `test/controllers/api/v1/company/projects/workflows_controller_test.rb`

**Frontend:**
- `app/frontend/features/workflows/api/workflowsApi.ts`
- `app/frontend/features/workflows/ui/CreateWorkflowDialog.tsx`
- `app/frontend/features/workflows/lib/workflowSchema.ts`

### Key files to modify

- `config/routes.rb` — add workflow routes at company and project levels
- `app/models/company.rb` — add `has_many :workflows, as: :scope`
- `app/models/project.rb` — add `has_many :workflows, as: :scope`

### Patterns to follow (reference: Agent/Tool)

- Controller: minimalist style (2-3 lines per action), `respond_with`, `paginate`, `ransack`
- Model: `# frozen_string_literal: true`, polymorphic scope, `merged_for_project`
- Serializer: inherits from `ApplicationSerializer`, includes `scope_indicator`
- Policy: mirrors controller namespace hierarchy
- Frontend: Feature-Sliced Design, RHF + Zod for forms, RTK Query for API
- Look at `app/models/tool.rb`, `app/controllers/api/v1/company/tools_controller.rb` as direct reference

### Dependencies

- None (first story in epic)
- Polymorphic scope pattern already established across 7+ models

### Testing

- Model: test validations (name presence, uniqueness per scope), associations, `merged_for_project` returns company + project, project overrides company by name
- Company controller: CRUD, admin-only
- Project controller: merged list, project-scoped create, authorization
- Use FactoryBot factories with `:company_scope` and `:project_scope` traits

### References

- [Source: ai/workflow-architecture.md#2.1](ai/workflow-architecture.md) — Workflow data model (updated: scope instead of project_id)
- [Source: ai/architecture/implementation-patterns-consistency-rules.md#Polymorphic Scoping](ai/architecture/implementation-patterns-consistency-rules.md) — Polymorphic scope pattern
- [Source: app/models/tool.rb](app/models/tool.rb) — Reference model with polymorphic scope
- [Source: app/controllers/api/v1/company/tools_controller.rb](app/controllers/api/v1/company/tools_controller.rb) — Reference company-scoped controller
- [Source: app/controllers/api/v1/company/projects/assets_controller.rb](app/controllers/api/v1/company/projects/assets_controller.rb) — Reference project-scoped controller
- [Source: ai/prd/functional-requirements.md#FR10](ai/prd/functional-requirements.md) — FR10: Admin can create new workflow

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus-high

### Debug Log References

- SystemStackError in responder for GET show — resolved by using ActionController::TestCase (matching project convention)
- AMS `config` attribute conflict — resolved by explicit `config` method delegation in serializer
- `has_many :steps` / `:runs` deferred — Step and WorkflowRun models not yet created (Story 12-2 / 12-6)

### Completion Notes List

- Created Workflow model with polymorphic scope (Company | Project), soft delete, merged_for_project
- Created WorkflowSerializer with scope_indicator, steps_count, last_run_at
- Created company and project WorkflowsControllers with CRUD actions
- Created Pundit policies for company (admin-only) and project (accessible) scopes
- Added routes at both company and project levels
- Created RTK Query workflowsApi with full CRUD for both scopes
- Created CreateWorkflowDialog with RHF + Zod validation
- All 29 backend tests passing, 0 regressions (1207 total tests)

### File List

- db/migrate/20260221211646_create_workflows.rb (new)
- app/models/workflow.rb (new)
- app/models/company.rb (modified — added has_many :workflows)
- app/models/project.rb (modified — added has_many :workflows)
- app/serializers/workflow_serializer.rb (new)
- app/controllers/api/v1/company/workflows_controller.rb (new)
- app/controllers/api/v1/company/projects/workflows_controller.rb (new)
- app/policies/api/v1/company/workflows_policy.rb (new)
- app/policies/api/v1/company/projects/workflows_policy.rb (new)
- config/routes.rb (modified — added workflow resources)
- test/factories/workflows.rb (new)
- test/models/workflow_test.rb (new)
- test/controllers/api/v1/company/workflows_controller_test.rb (new)
- test/controllers/api/v1/company/projects/workflows_controller_test.rb (new)
- app/frontend/features/workflows/api/workflowsApi.ts (new)
- app/frontend/features/workflows/ui/CreateWorkflowDialog.tsx (new)
- app/frontend/features/workflows/lib/workflowSchema.ts (new)
- app/frontend/features/workflows/lib/types.ts (new)
- app/frontend/shared/api/routes.ts (regenerated — added workflow routes)

### Change Log

- 2026-02-21: Story 12-1 implemented — Workflow model, API, policies, frontend API layer, all tests passing
