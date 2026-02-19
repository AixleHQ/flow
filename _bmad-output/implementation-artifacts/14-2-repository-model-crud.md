# Story 14.2: Repository Model + CRUD

Status: ready-for-dev

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

- [ ] Task 1: Database migration (AC: #1)
  - [ ] 1.1 Create `repositories` table: `full_name` (string, not null), `default_branch` (string, not null, default: 'main'), `clone_url` (string, not null), `is_private` (boolean, default: false), `description` (text), `last_fetched_at` (datetime), `integration_id` (bigint, not null, FK to integrations), `scope_type` (string, not null), `scope_id` (bigint, not null), `timestamps`
  - [ ] 1.2 Add indexes: `[scope_type, scope_id, full_name]` unique (no duplicate repos in same scope), `[scope_type, scope_id]`, `[integration_id]`

- [ ] Task 2: Repository model (AC: #1, #5)
  - [ ] 2.1 `belongs_to :scope, polymorphic: true` (Company | Project)
  - [ ] 2.2 `belongs_to :integration`
  - [ ] 2.3 Validations: full_name presence + format (`owner/repo`), full_name uniqueness within scope, default_branch presence, clone_url presence, scope_type inclusion `%w[Company Project]`
  - [ ] 2.4 Scopes: `for_company(company)`, `for_project(project)`, `for_integration(integration)`
  - [ ] 2.5 `merged_for_project(project)` — returns company + project repos with `scope_indicator`, follows exact Skill model pattern
  - [ ] 2.6 Convenience method: `repo_name` — returns last segment of full_name (e.g. "my-app" from "acme/my-app")
  - [ ] 2.7 Add `has_many :repositories, as: :scope, dependent: :destroy` to Company and Project models
  - [ ] 2.8 Ransackable attributes for filtering

- [ ] Task 3: GitHub repos listing service (AC: #2)
  - [ ] 3.1 Create `Github::RepositoryService` in `app/services/github/repository_service.rb`
  - [ ] 3.2 Method `list_available(integration)` — generates installation token via `Github::TokenService`, calls `GET /installation/repositories` via Octokit, returns array of `{ full_name, default_branch, clone_url, private, description }`
  - [ ] 3.3 Pagination support — GitHub API returns max 100 per page, iterate all pages
  - [ ] 3.4 Error handling — return empty array + log on auth failure

- [ ] Task 4: Company-level controller (AC: #2, #3, #4)
  - [ ] 4.1 `Api::V1::Company::RepositoriesController` — index, show, create, destroy, available
  - [ ] 4.2 `index` — `current_company.repositories` with ransack
  - [ ] 4.3 `create` — accepts `{ integration_id, full_name, default_branch (optional) }`, fetches repo info from GitHub API to populate clone_url/is_private/description, creates Repository scoped to company
  - [ ] 4.4 `destroy` — hard delete
  - [ ] 4.5 `available` — accepts `integration_id` param, returns available repos from GitHub API via `Github::RepositoryService`. Custom action: `GET /api/v1/company/repositories/available?integration_id=X`
  - [ ] 4.6 Routes: `resources :repositories, only: %i[index show create destroy] do; collection { get :available }; end`

- [ ] Task 5: Project-level controller (AC: #4, #5)
  - [ ] 5.1 `Api::V1::Company::Projects::RepositoriesController` — index, create, destroy, available
  - [ ] 5.2 `index` — `Repository.merged_for_project(current_project)` with scope_indicator
  - [ ] 5.3 `create` — same as company but scoped to project
  - [ ] 5.4 `destroy` — only project-scoped repos, not company-inherited
  - [ ] 5.5 `available` — same as company level (integration is company-level)
  - [ ] 5.6 Routes: nested under projects, same actions

- [ ] Task 6: Serializer (AC: #7)
  - [ ] 6.1 `RepositorySerializer < ApplicationSerializer` — id, full_name, repo_name, default_branch, clone_url, is_private, description, last_fetched_at, scope_type, scope_id, scope_indicator, integration (nested: id, name, provider), created_at
  - [ ] 6.2 `scope_indicator` — "company" or "project", same logic as SkillSerializer

- [ ] Task 7: Policies (AC: #6)
  - [ ] 7.1 `Api::V1::Company::RepositoriesPolicy` — admin only (create, destroy), all company users (index, show, available)
  - [ ] 7.2 `Api::V1::Company::Projects::RepositoriesPolicy` — `project_accessible?` for all actions

- [ ] Task 8: Frontend — RTK Query API (AC: #7)
  - [ ] 8.1 Create `features/repositories-management/api/repositoriesApi.ts`
  - [ ] 8.2 Endpoints: `getCompanyRepositories`, `getProjectRepositories` (merged), `getAvailableRepositories` (query with integration_id param), `createCompanyRepository`, `createProjectRepository`, `deleteCompanyRepository`, `deleteProjectRepository`
  - [ ] 8.3 Add `QueryTag.Repositories` to `shared/api/QueryTag.ts`
  - [ ] 8.4 Types in `features/repositories-management/lib/types.ts`: `Repository`, `AvailableRepo`, `CreateRepositoryRequest`

- [ ] Task 9: Frontend — Repository UI (AC: #7)
  - [ ] 9.1 Create `features/repositories-management/ui/RepositoriesPanel.tsx` — accepts optional `projectId` prop. Shows list/cards with repo full_name, branch badge, private/public icon, scope indicator, integration name, delete button
  - [ ] 9.2 Create `features/repositories-management/ui/AddRepositoryDialog.tsx` — step 1: select integration (dropdown, skip if only one), step 2: search/select repo from available list, step 3: optionally override branch. Uses React Hook Form + Zod.
  - [ ] 9.3 Zod schema: `features/repositories-management/lib/repositorySchema.ts` — validates integration_id required, full_name required
  - [ ] 9.4 Add "Repositories" tab to Project page (`ProjectPage.tsx` VALID_TABS)
  - [ ] 9.5 Create `pages/repositories/ui/RepositoriesPage.tsx` — thin wrapper for company-level view
  - [ ] 9.6 Add route to `routeTree.tsx` and `shared/routes.ts` for company-level
  - [ ] 9.7 Add navigation to company settings area (alongside Integrations)

- [ ] Task 10: Tests (AC: all)
  - [ ] 10.1 Repository model test — validations (full_name format, uniqueness within scope), scopes (for_company, for_project, for_integration), merged_for_project with scope_indicator, associations, repo_name method
  - [ ] 10.2 Github::RepositoryService test — mock Octokit calls, pagination, error handling
  - [ ] 10.3 Company::RepositoriesController test — index, create (mocked GitHub), destroy, available (mocked), authorization
  - [ ] 10.4 Projects::RepositoriesController test — index (merged), create (project-scoped), destroy (only own), authorization
  - [ ] 10.5 Factory: `repository` factory with traits `:company_scope`, `:project_scope`, `:private`

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

### Debug Log References

### Completion Notes List

### File List
