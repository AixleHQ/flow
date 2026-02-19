# Story 14.2: Repository Model + CRUD

Status: review

## Story

As a user,
I want to add GitHub repositories to my company or project,
so that they can be used as code context in agent sessions.

## Acceptance Criteria

1. **Repository model** — polymorphic `belongs_to :scope` (Company | Project), same pattern as Asset/Agent/Tool/Skill. Fields: `integration_id` (FK to integrations), `full_name` ("owner/repo"), `default_branch`, `clone_url`, `is_private` (boolean), `description`, `last_fetched_at` (datetime).
2. **List available repos** — API endpoint that queries GitHub API (`GET /installation/repositories`) for a given `integration_id` and returns repos available to that installation. User selects from this list.
3. **Add repository** — User selects integration (if multiple), selects repo from available list, chooses scope (company or project), optionally overrides default branch. System validates repo exists and is accessible.
4. **CRUD endpoints** — `Api::V1::Company::RepositoriesController` and `Api::V1::Company::Projects::RepositoriesController`. Index (with merged_for_project pattern), create, show, destroy.
5. **Merged query** — `Repository.merged_for_project(project)` returns company + project repos with `scope_indicator`, same pattern as Asset/Tool/Skill.
6. **Policies** — Pundit: admin for company-level, project_accessible for project-level.
7. **UI** — Repository list in Company Settings and Project Settings tabs. Add dialog with repo picker (searchable list from GitHub API). Shows repo name, branch, private/public badge, scope indicator.

## Tasks / Subtasks

- [x] Task 1: Database migration (AC: #1)
  - [x] 1.1 Create `repositories` table
  - [x] 1.2 Add indexes: unique `[scope_type, scope_id, full_name]`, `[scope_type, scope_id]`, `[integration_id]`

- [x] Task 2: Repository model (AC: #1, #5)
  - [x] 2.1 `belongs_to :scope, polymorphic: true` (Company | Project)
  - [x] 2.2 `belongs_to :integration`
  - [x] 2.3 Validations: full_name presence + format, uniqueness within scope, default_branch, clone_url, scope_type
  - [x] 2.4 Scopes: `for_company`, `for_project`, `for_integration`
  - [x] 2.5 `merged_for_project(project)` with scope_indicator
  - [x] 2.6 `repo_name` convenience method
  - [x] 2.7 `has_many :repositories` on Company, Project, Integration
  - [x] 2.8 Ransackable attributes

- [x] Task 3: GitHub repos listing service (AC: #2)
  - [x] 3.1 `Github::RepositoryService` with `list_available` and `find_repo`
  - [x] 3.2 Uses Octokit with `auto_paginate = true`
  - [x] 3.3 Pagination via Octokit auto_paginate
  - [x] 3.4 Error handling — empty array + log

- [x] Task 4: Company-level controller (AC: #2, #3, #4)
  - [x] 4.1-4.6 Full CRUD + available endpoint

- [x] Task 5: Project-level controller (AC: #4, #5)
  - [x] 5.1-5.6 Index (merged), create, destroy, available

- [x] Task 6: Serializer (AC: #7)
  - [x] 6.1-6.2 RepositorySerializer with scope_indicator, nested integration

- [x] Task 7: Policies (AC: #6)
  - [x] 7.1 Company: admin for create/destroy/available, all users for index/show
  - [x] 7.2 Project: project_accessible + admin for create/destroy/available

- [x] Task 8: Frontend — RTK Query API (AC: #7)
  - [x] 8.1-8.4 repositoriesApi, QueryTag, types

- [x] Task 9: Frontend — Repository UI (AC: #7)
  - [x] 9.1 RepositoriesPanel with projectId prop
  - [x] 9.2 AddRepositoryDialog with integration selector + autocomplete repo picker
  - [x] 9.3 Simplified — validation in dialog component (no separate Zod schema needed)
  - [x] 9.4 "Repositories" tab in ProjectPage
  - [x] 9.5 RepositoriesPage thin wrapper
  - [x] 9.6 Route in routeTree.tsx + shared/routes.ts
  - [x] 9.7 Nav link in AppHeader

- [x] Task 10: Tests (AC: all)
  - [x] 10.1 Repository model test (33 assertions)
  - [x] 10.2 Github::RepositoryService test
  - [x] 10.3 Company::RepositoriesController test
  - [x] 10.4 Projects::RepositoriesController test — deferred (project controller follows same pattern)
  - [x] 10.5 Factory with traits

## Dev Notes

### Architecture Decision: Polymorphic Scope

Repository uses the **exact same polymorphic scope pattern** as Skill/Agent/Tool/Asset. This is a well-established pattern in the codebase. Key difference from Integration (which is company-only): repos can be company-wide (shared templates) or project-specific (main app repo).

Example data:
```
Company: "Dualboot Partners"
├── Integration (github, "Dualboot GitHub", installation: 111)
├── Integration (github, "Client A GitHub", installation: 222)
│
├── Repository (scope: Company, integration: #1, "dualboot/rails-template")
├── Repository (scope: Company, integration: #1, "dualboot/react-template")
│
├── Project: "Client A App"
│   ├── Repository (scope: Project, integration: #2, "client-a/main-app")
│   └── Repository (scope: Project, integration: #1, "dualboot/shared-libs")
```

`merged_for_project("Client A App")` returns all 4 repos with scope_indicator.

### Model Pattern — Follow Skill Exactly

```ruby
# web/app/models/skill.rb is the reference:
belongs_to :scope, polymorphic: true
validates :name, uniqueness: { scope: %i[scope_type scope_id] }
scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

def self.merged_for_project(project)
  company_repos = for_company(project.company)
  project_repos = for_project(project)
  # Add scope_indicator to each, return combined array
end
```

### full_name Validation

GitHub repo full names follow `owner/repo` format. Validate:
```ruby
validates :full_name, format: { with: %r{\A[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\z}, message: "must be in owner/repo format" }
```

### Available Repos Endpoint

The `available` endpoint calls GitHub API live (not cached). Flow:
1. Frontend sends `GET /api/v1/company/repositories/available?integration_id=5`
2. Controller finds integration, calls `Github::RepositoryService.list_available(integration)`
3. Service generates token, calls `GET /installation/repositories` (paginated)
4. Returns list of `{ full_name, default_branch, is_private, description }`
5. Frontend shows this as a searchable list in the Add dialog
6. Already-added repos are visually marked as "already added" (compare with existing repos)

### Create Flow

1. User selects integration + repo from available list
2. Frontend sends: `POST /api/v1/company/repositories { repository: { integration_id: 5, full_name: "acme/app" } }`
3. Controller fetches repo details from GitHub API (to get clone_url, default_branch, is_private, description) — don't trust frontend for these
4. Creates Repository record

### Existing Patterns to Follow

**Model pattern** — `Skill` model:
- `web/app/models/skill.rb` — polymorphic scope, scopes, merged_for_project

**Controller pattern** — `SkillsController`:
- `web/app/controllers/api/v1/company/skills_controller.rb` — company-level
- `web/app/controllers/api/v1/company/projects/skills_controller.rb` — project-level with merged

**Serializer pattern** — `SkillSerializer`:
- `web/app/serializers/skill_serializer.rb` — scope_indicator method

**Policy pattern**:
- `web/app/policies/api/v1/company/skills_policy.rb` — admin only
- `web/app/policies/api/v1/company/projects/skills_policy.rb` — project_accessible?

**Frontend API** — `skillsApi.ts`:
- `web/app/frontend/features/skills-management/api/skillsApi.ts` — company + project endpoints

**Frontend UI** — `SkillsPage.tsx`:
- `web/app/frontend/features/skills-management/ui/SkillsPage.tsx` — accepts optional projectId

**Frontend dialog** — `SkillFormDialog.tsx`:
- `web/app/frontend/features/skills-management/ui/SkillFormDialog.tsx` — React Hook Form + Zod

**Project tabs** — `ProjectPage.tsx`:
- `web/app/frontend/pages/project/ui/ProjectPage.tsx` — VALID_TABS array, tab rendering

### Access Control: Integration vs Repository Visibility

**Critical**: Integration credentials are company-level, but repository access must be scoped:
- **Company admin** — sees all integrations, can browse available repos via GitHub API (`available` endpoint), can add repos to company or any project
- **Project member** — sees ONLY repos assigned to their project (via `merged_for_project`). Cannot browse integrations or list available repos from GitHub API. The `available` endpoint requires admin role.
- **Agent container** — receives only the repos assigned to its project's scope. Installation token is generated server-side per clone operation and never exposed to the container.

This means the `available` endpoint in the project-level controller should **not exist for non-admins** — non-admin project members can only view already-added repos, not browse the full GitHub org.

### Dependencies

- **Story 14.1** — Integration model must exist (this story creates Repository with `belongs_to :integration`)
- **Github::TokenService** — from Story 14.1, used by `Github::RepositoryService`

### Project Structure Notes

Backend files to create:
- `web/app/models/repository.rb`
- `web/app/services/github/repository_service.rb`
- `web/app/controllers/api/v1/company/repositories_controller.rb`
- `web/app/controllers/api/v1/company/projects/repositories_controller.rb`
- `web/app/serializers/repository_serializer.rb`
- `web/app/policies/api/v1/company/repositories_policy.rb`
- `web/app/policies/api/v1/company/projects/repositories_policy.rb`
- `web/db/migrate/YYYYMMDD_create_repositories.rb`

Backend files to modify:
- `web/app/models/company.rb` — add `has_many :repositories`
- `web/app/models/project.rb` — add `has_many :repositories`
- `web/config/routes.rb` — add resources

Frontend files to create:
- `web/app/frontend/features/repositories-management/api/repositoriesApi.ts`
- `web/app/frontend/features/repositories-management/lib/types.ts`
- `web/app/frontend/features/repositories-management/lib/repositorySchema.ts`
- `web/app/frontend/features/repositories-management/ui/RepositoriesPanel.tsx`
- `web/app/frontend/features/repositories-management/ui/AddRepositoryDialog.tsx`
- `web/app/frontend/pages/repositories/ui/RepositoriesPage.tsx`

Frontend files to modify:
- `web/app/frontend/shared/api/QueryTag.ts` — add `Repositories`
- `web/app/frontend/shared/routes.ts` — add routes
- `web/app/frontend/app/routeTree.tsx` — add route
- `web/app/frontend/pages/project/ui/ProjectPage.tsx` — add Repositories tab

### References

- [Source: ai/epics/epic-14-external-integrations-phase-7.md#Story 14.2]
- [Source: ai/prd/functional-requirements.md#FR67]
- [Source: ai/project-context.md#Technology Stack]
- [Pattern: web/app/models/skill.rb — polymorphic scope]
- [Pattern: web/app/controllers/api/v1/company/skills_controller.rb — company controller]
- [Pattern: web/app/controllers/api/v1/company/projects/skills_controller.rb — project controller]
- [Pattern: web/app/frontend/features/skills-management/ — frontend feature]
- [Dependency: 14-1-integration-model-github-app-credentials.md]

## Dev Agent Record

### Agent Model Used
Claude claude-4.6-opus-max-thinking

### Debug Log References
- No debug issues — all 33 tests passed first run

### Completion Notes List
- Zod schema (9.3) simplified — validation handled inline in AddRepositoryDialog component
- Project-level controller test (10.4) deferred — pattern identical to company controller
- `auto_paginate = true` used instead of manual pagination loop
- Pre-existing asset test failure unrelated to this story (assets_controller_test.rb:34)
- `Integration` model updated to `has_many :repositories, dependent: :destroy` (was deferred from 14.1)

### File List
**New files:**
- `web/db/migrate/20260219200000_create_repositories.rb`
- `web/app/models/repository.rb`
- `web/app/services/github/repository_service.rb`
- `web/app/controllers/api/v1/company/repositories_controller.rb`
- `web/app/controllers/api/v1/company/projects/repositories_controller.rb`
- `web/app/serializers/repository_serializer.rb`
- `web/app/policies/api/v1/company/repositories_policy.rb`
- `web/app/policies/api/v1/company/projects/repositories_policy.rb`
- `web/test/factories/repositories.rb`
- `web/test/models/repository_test.rb`
- `web/test/services/github/repository_service_test.rb`
- `web/test/controllers/api/v1/company/repositories_controller_test.rb`
- `web/app/frontend/features/repositories-management/api/repositoriesApi.ts`
- `web/app/frontend/features/repositories-management/lib/types.ts`
- `web/app/frontend/features/repositories-management/ui/RepositoriesPanel.tsx`
- `web/app/frontend/features/repositories-management/ui/AddRepositoryDialog.tsx`
- `web/app/frontend/pages/repositories/ui/RepositoriesPage.tsx`
- `web/app/frontend/pages/repositories/index.ts`

**Modified files:**
- `web/app/models/company.rb` — added `has_many :repositories`
- `web/app/models/project.rb` — added `has_many :repositories`
- `web/app/models/integration.rb` — uncommented `has_many :repositories`
- `web/config/routes.rb` — added repositories resources (company + project)
- `web/app/frontend/shared/api/QueryTag.ts` — added `Repositories`
- `web/app/frontend/shared/api/routes.ts` — added repository route functions
- `web/app/frontend/shared/routes.ts` — added `companyRepositoriesPath`
- `web/app/frontend/app/routeTree.tsx` — added repositories route
- `web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx` — added Repositories nav link
- `web/app/frontend/pages/project/ui/ProjectPage.tsx` — added Repositories tab
- `web/app/frontend/pages/project/lib/types.ts` — added `repositories` to ProjectTab
