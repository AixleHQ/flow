# Plan: Remove Company-Level Versions of 7 Entities (Workflow Catalog Replacement)

> Branch: `feature/remove-company-level-entities` (off `develop`).
> Status: research complete, verified against the codebase. Implementation pending decisions in §6.

## 1. Overview & scope

The Workflow Catalog feature replaces the **company-level** screens for seven entities: **Integrations, Repositories, Agents, Tools, Skills, McpServers, Workflows**. This plan removes the company-level web surface, the duplicate top-level `api/v1` workflows API, the company-level frontend pages, and their tests/policies. It **preserves** the project-level versions, the shared models, and the new `workflow_catalog` feature.

### Ownership model (as discovered)

- **Six entities** (`Repository`, `Agent`, `Tool`, `Skill`, `MCPServer`, `Workflow`) use a **polymorphic `scope`** (`scope_type` ∈ `Company | Project | System`, `scope_id`). Company and Project rows live in the **same table**, distinguished only by `scope_type`.
- **Integration** is the exception: it uses `company_id` (NOT NULL) + optional `project_id`. `project_id IS NULL` ⇒ company-wide; a present `project_id` ⇒ project-scoped (a `Repository` then hangs off the integration via `integration_id`).
- Because every table is **shared** across company/project scope, the **models, columns, factories, and model tests MUST STAY**. This is a removal of *UI / controllers / routes*, not of data or models.

### Explicitly kept (high level — full list in §5)

- All 7 ActiveRecord models and their scopes (including `for_company` / `visible_for_company` / `company_wide`, which become caller-light but are still referenced by kept features).
- **`workflow_catalog`** (controller, page, policy) — the replacement feature. It has **no model of its own**; it reads existing `Workflow` rows via `Workflow.published_in_company` → `belonging_to_company` (which spans **both** Company- and Project-scoped published workflows). Therefore `belonging_to_company` / `published_in_company` are **load-bearing** and must stay. (Verified: `app/models/workflow.rb:27,37`, `workflow_catalog_controller.rb:5,18`.)
- All **project-level** controllers/pages/tests under `web/company/projects/`, `api/v1/projects/workflows*`, and `pages/Projects/*`.
- All **shared resource components** (`shared/resources/*Content.tsx`) — imported by both Company and Projects pages.
- `Web::Company::ApplicationController` (shared base) and `Web::Company::SessionsController` (stays, with a picker decision — see §6.8).
- The **Administrate admin** surface (scope-agnostic, read-only) — recommended keep (see §6.4).

### Reconciled notes

- **Top-level `api/v1` workflows** (routes ~52–60, `Api::V1::WorkflowsController` + `api/v1/workflows/`): confirmed **company-scoped** (`Workflow.for_company(current_company)`, verified `api/v1/workflows_controller.rb:6`) and a duplicate of the project-nested API. **Remove it.** The project-nested API (`api/v1/projects/workflows*`) stays.
- **github_setup callback**: the company integrations controller **uniquely hosts the only GitHub App callback** (`github_setup`). The callback must be **relocated, not deleted** — see §2.

---

## 2. Integrations callback fix (first-class requirement)

### Current behavior

- There is exactly **one** GitHub App callback endpoint in the app: `GET /company/integrations/github_setup` → `Web::Company::IntegrationsController#github_setup` (`config/routes.rb` ~196–200). The GitHub App **Setup URL** on GitHub.com points here, so **every** GitHub App install — company or project — lands on this company-level action.
- The action already supports project routing: the frontend (`app/frontend/shared/resources/integrations/IntegrationsContent.tsx` ~84–91) builds the install URL with `?state=project:<id>` when on a project page. `github_setup` reads `params[:state]`, resolves the project via `resolve_github_setup_project`, and `github_setup_redirect_path` redirects to `company_project_integrations_path(project)` when a project is present, else to `company_integrations_path`.
- **Problem**: deleting `Web::Company::IntegrationsController` and its route deletes the **only** callback endpoint and breaks the project GitHub-connect flow. Also `company_integrations_path` (the non-project fallback) will no longer exist.

### Desired behavior

Project-initiated GitHub integration connects must **always** return to the **project** (`company_project_integrations_path(project)`), and the callback must keep functioning after the company integrations screen is gone.

### Exact change

1. **Keep the same fixed URL** `GET /company/integrations/github_setup` so the GitHub App Setup URL on GitHub.com needs **no reconfiguration** (it is a single global value, cannot be project-specific; the project target rides in `state`). Relocate the action onto a slim surviving controller — recommended: a new `Web::Company::Integrations::GithubSetupController#github_setup` under the kept `namespace :company`.

   Route (replacing the deleted `resources :integrations` block):
   ```ruby
   # under namespace :company
   get "integrations/github_setup", to: "integrations/github_setup#github_setup", as: :company_integrations_github_setup
   ```

2. **Move these from the deleted controller into the new one**, unchanged in logic:
   - `github_setup` action (lines ~17–56)
   - `resolve_github_setup_project` (~108–115)
   - `github_setup_redirect_path` (~104–106)
   - `skip_before_action :dynamic_authorize!, only: :github_setup` (line 4) — preserve the skip; GitHub calls this endpoint without app session context. Authorization relies on the in-action `accessible_by?` checks (~26–29).
   - The `Integration.find_or_build_github_for_installation(project:)` + `Github::TokenService` verification logic stays as-is.

3. **Repoint the redirect fallbacks** (the deleted `company_integrations_path` no longer exists):
   - Success and blank-`installation_id` cases → `company_project_integrations_path(target_project)`.
   - Inaccessible-project / missing-`state` error cases → `company_projects_path`, with an alert telling the user to install from within a project.
   - Concretely: drop the `: company_integrations_path` branch in `github_setup_redirect_path`, and change the line ~27 `redirect_to company_integrations_path` to `company_projects_path`.

4. **Policy**: create a `github_setup?` permission for the new controller (slim policy), preserving the unauthenticated-context skip pattern.

5. **Frontend** (`IntegrationsContent.tsx`):
   - Line ~85 fallback `return '/company/integrations/github_setup'` — **no change needed** since the URL is kept. The project branch (~89, `state=project:<id>`) is the load-bearing path and must remain.
   - The bare company (non-project) branch of `getGithubInstallUrl` becomes unreachable once company nav entries are gone; may be dropped as cleanup.

> GitLab and Coder use **no** OAuth callback (PAT/token submitted directly via `*::IntegrationService` with `project:`). Webhooks (`Webhooks::GithubController`/`GitlabController`) key off repository `full_name` only — scope-agnostic, **unaffected**.

---

## 3. Deletion inventory

### (a) Routes — `config/routes.rb`

| Lines (approx) | What | Note |
|---|---|---|
| 52–60 | Top-level `resources :workflows do scope module: :workflows … resources :steps … reorder end end` | Company-scoped API. Remove. |
| 196–200 | `resources :integrations … do collection { get :github_setup } end` | Remove the resource block, but **re-add** a standalone `github_setup` route (see §2). |
| 201 | `resources :repositories` | Remove. |
| 248 | `resources :agents` | Remove. |
| 249 | `resources :tools` | Remove. |
| 250 | `resources :skills` | Remove. |
| 251 | `resources :mcp_servers` | Remove. |
| 252–256 | `resources :workflows do member { get :builder } end` (company web) | Remove. |

> **Do NOT touch**: the project-nested block (`resources :projects do scope module: :projects … end`, ~202–247), `workflow_catalog` (~257–261), `analytics`/`assets`/`sessions`/`members`/`config_items`, the `api/v1/projects/workflows*` block (~70–78), and the **admin** namespace (~125–170).

### (b) Web & API controllers

| Path | What |
|---|---|
| `app/controllers/web/company/repositories_controller.rb` | whole file |
| `app/controllers/web/company/agents_controller.rb` | whole file |
| `app/controllers/web/company/tools_controller.rb` | whole file |
| `app/controllers/web/company/skills_controller.rb` | whole file |
| `app/controllers/web/company/mcp_servers_controller.rb` | whole file (`Web::Company::MCPServersController`) |
| `app/controllers/web/company/workflows_controller.rb` | whole file |
| `app/controllers/web/company/integrations_controller.rb` | whole file **after relocating `github_setup`** (see §2) |
| `app/controllers/api/v1/workflows_controller.rb` | whole file |
| `app/controllers/api/v1/workflows/steps_controller.rb` | whole file |
| `app/controllers/api/v1/workflows/application_controller.rb` | whole file — delete the entire `app/controllers/api/v1/workflows/` directory |

### (c) Policies

| Path | What |
|---|---|
| `app/policies/web/company/repositories_policy.rb` | whole file |
| `app/policies/web/company/agents_policy.rb` | whole file |
| `app/policies/web/company/tools_policy.rb` | whole file |
| `app/policies/web/company/skills_policy.rb` | whole file |
| `app/policies/web/company/mcp_servers_policy.rb` | whole file |
| `app/policies/web/company/workflows_policy.rb` | whole file |
| `app/policies/web/company/integrations_policy.rb` | whole file (recreate `github_setup?` on the relocated controller's policy — see §2) |
| `app/policies/web/company/workflows/` | dir (company steps policy) — delete; project steps policy stays |

> KEEP `app/policies/web/company/workflow_catalog_policy.rb` and all `app/policies/web/company/projects/*`.

### (d) Frontend pages

| Path | What |
|---|---|
| `app/frontend/pages/Company/Agents` | whole dir |
| `app/frontend/pages/Company/Tools` | whole dir |
| `app/frontend/pages/Company/Skills` | whole dir |
| `app/frontend/pages/Company/McpServers` | whole dir |
| `app/frontend/pages/Company/Repositories` | whole dir |
| `app/frontend/pages/Company/Integrations` | whole dir |
| `app/frontend/pages/Company/Workflows` | whole dir |

> Inertia resolves pages by glob — no manual registry, so deleting directories is sufficient. KEEP `Company/{Analytics,Assets,ConfigItems,Members,Sessions,WorkflowCatalog}`.

### (e) Tests

| Path | What |
|---|---|
| `test/integration/web/company/agents_controller_test.rb` | whole file |
| `test/integration/web/company/tools_controller_test.rb` | whole file |
| `test/integration/web/company/skills_controller_test.rb` | whole file |
| `test/integration/web/company/mcp_servers_controller_test.rb` | whole file |
| `test/integration/web/company/integrations_controller_test.rb` | whole file (the `github_setup` flow tests → **moved/rewritten** against the relocated controller) |
| `test/integration/web/company/repositories_controller_test.rb` | whole file |
| `test/integration/web/company/workflows_controller_test.rb` | whole file |
| `test/controllers/api/v1/workflows_controller_test.rb` | whole file |
| `test/controllers/api/v1/workflows/steps_controller_test.rb` | whole file |

> Exact filenames to be confirmed at delete time (`git ls-files test | grep …`). KEEP all `test/integration/web/company/projects/*`, kept company-feature tests (`workflow_catalog`, `analytics`, `assets`, `config_items`, `members`, `projects`, `sessions`), all model tests, all factories (incl. company-scope traits), and `api/v1/projects/workflows*` tests.

### (f) i18n

**No changes.** `config/locales/en.yml` contains no nav/title/entity keys for these features — nav labels are hardcoded in `AppSidebar.tsx`.

### (g) Services / serializers

**No deletions.** All Alba/Typelizer Resources (`agent_resource`, `tool_resource`, `skill_resource`, `mcp_server_resource`, `workflow_resource`, `repository_resource`, `integration_resource`, `picker_resource`) are shared with project scope and kept APIs. All services (`workflow_service`, `workflow_duplicator`, `skills_registry_service`, `repository_service`, workflow/company analytics) are used by kept code. (Seed re-scoping is in §4 / §6.9.)

---

## 4. Files to MODIFY (not delete)

### `config/routes.rb`
Remove the blocks in §3(a); **add** the standalone `github_setup` route from §2.

### `app/frontend/shared/ui/AppSidebar.tsx`
- Remove the entire **"Shared Library"** company nav group (`companyNavGroups`, lines ~152–168): Agents, Tools, Skills, MCP Servers, Repositories, Integrations, Workflows.
- Remove the now-unused `shared/routes` imports: `companyAgentsPath`, `companyIntegrationsPath`, `companyMCPServersPath`, `companyRepositoriesPath`, `companySkillsPath`, `companyToolsPath`, `companyWorkflowsPath`.
- **KEEP** all `companyProject*Path` imports/items and the other company helpers used elsewhere (`companyAssetsPath`, `companyConfigItemsPath`, `companyMembersPath`, `companySessionsPath`, `companyProjectsPath`).
- **KEEP** the `@tabler` icon imports — still used by `buildProjectNavGroups` (lines ~104, 112–117). Remove an icon import only if a final grep confirms it is unused.
- (Optional, recommended) Add a **Workflow Catalog** nav entry to the company nav, since it is the replacement. The sidebar currently has no catalog link. Out of strict removal scope — flag with the user.

### `app/frontend/pages/Projects/Workflows/BuilderPage.tsx`
This editor is **shared** but, after removal, only ever renders **with a `projectId`**. Strip the company fallbacks that reference soon-deleted helpers:
- `backPath` ternary `projectId ? … : '/company/workflows'` → drop the `'/company/workflows'` branch.
- The four API helpers (`workflowApi` / `stepsCollectionApi` / `stepApi` / `stepsReorderApi`) each `projectId ? apiV1Project… : apiV1Workflow…` — the company branches use the **removed** `apiV1WorkflowPath` / `apiV1WorkflowStepsPath` / `apiV1WorkflowStepPath` / `reorderApiV1WorkflowStepsPath`. Drop the company branches (treat `projectId` as non-null) and remove the now-unused `apiV1Workflow*` imports.

> Verified: the only FE importers of the doomed helpers are `AppSidebar.tsx` and `BuilderPage.tsx` (plus the generated `routes.ts`).

### `app/frontend/shared/resources/integrations/IntegrationsContent.tsx`
- Line ~85 fallback `/company/integrations/github_setup`: **no change** (URL preserved). The project branch (`state=project:<id>`) must remain.
- KEEP the `scopeIndicator === 'company'` filtering — the read-only "Company-wide" section in the **project** integrations view stays. Confirm any "show link" target no longer links to the deleted company integrations page.

### `app/frontend/shared/routes.ts`
**Do NOT hand-edit** — generated by `ts_routes-rails` (`rake ts:routes`). After the routes change, **regenerate** so the company `*Path` and `apiV1Workflow*` helpers drop cleanly.

### `app/models/company.rb`
**KEEP associations as-is** (`has_many :agents/:tools/:mcp_servers/:skills/:repositories/:workflows, as: :scope` and `has_many :integrations`). They are still exercised by the kept `Web::Company::SessionsController` and the catalog. Removing them would break Sessions/catalog. **No model change.**

### `app/controllers/web/company/sessions_controller.rb`
`#new` (verified, lines ~24–44) builds pickers from `Agent.belonging_to_company` / `Tool|Skill|MCPServer|Repository.visible_for_company`. `visible_for_company` is **company-scoped only**, so Tools/Skills/MCPServers/Repositories pickers go **empty** once company-level rows stop being created (Agents uses `belonging_to_company`, still spans projects). **Decision required** (§6.8).

### `app/services/company_overview_service.rb` — DONE
`workflows_scope` else-branch now counts workflows **through the company's projects**: `company.workflows.active`, where `Company has_many :workflows, through: :projects` (replacing the old company-scoped `has_many :workflows, as: :scope`). Company-level workflows no longer count; the company's workflow total is the aggregate of its projects' active workflows. Cascade on company destroy is preserved via `projects → workflows`.

### Seeds (re-scope, not blind delete — see §6.9)
- `db/seeds.rb`: company MCP server block (`test_company.mcp_servers.find_or_create_by!`), `Seeds::Semgrep.seed!(test_company)`, `Seeds::CodeReport.seed!(test_company)`.
- `db/seeds/semgrep.rb`: Company-scoped `Tool`.
- `db/seeds/code_report.rb`: Company-scoped `Agent` + `Workflow` + Asset.
- `db/seeds/aixle_builder.rb`: **prose** describing "Workflows (company-level — inherited by all projects)" — no DB entities; **update the prose**.

---

## 5. Explicit KEEP list (prevent over-deletion)

**Models & scopes**
- `app/models/{integration,repository,agent,tool,skill,mcp_server,workflow}.rb` — shared, required by project scope + catalog.
- Scopes: `belonging_to_company` and `published_in_company` are **load-bearing** (catalog). `for_company` / `visible_for_company` / `company_wide` become caller-light but are still used by `SessionsController`; **leave on the models**.
- `app/models/company.rb` & `project.rb` associations — keep all.
- `app/models/namespace_resource_quota.rb` — unrelated (Project/User k8s quotas). Do not touch.

**Controllers / policies (project + shared + replacement)**
- `app/controllers/web/company/application_controller.rb` (shared base).
- `app/controllers/web/company/workflow_catalog_controller.rb` + `workflow_catalog_policy.rb`.
- `app/controllers/web/company/sessions_controller.rb` (picker decision §6.8).
- Entire `app/controllers/web/company/projects/` tree.
- `app/controllers/api/v1/projects/workflows_controller.rb` and `api/v1/projects/workflows/`.
- `app/controllers/web/application_controller.rb` (shares `github_app_slug` inertia prop).
- `app/controllers/webhooks/github_controller.rb`, `webhooks/gitlab_controller.rb`.
- Admin namespace controllers + dashboards (recommended keep — §6.4).

**Services / serializers** — all Alba Resources and all services in §3(g); `app/services/github/*`; `app/resources/integration_resource.rb`.

**Frontend**
- `app/frontend/shared/resources/{agents,integrations,mcp-servers,repositories,skills,tools}/*Content.tsx` (+ tests).
- Entire `app/frontend/pages/Projects/` (incl. `Workflows/WorkflowsPage.tsx` and `Workflows/BuilderPage.tsx`, the latter edited not deleted).
- `app/frontend/pages/Company/{Analytics,Assets,ConfigItems,Members,Sessions,WorkflowCatalog}/`.
- `app/frontend/types/generated/` (regenerated, not edited).
- `app/frontend/shared/routes.ts` (regenerated, never hand-edited).

**Tests / fixtures / docs / i18n** — all model tests, all factories incl. company-scope traits, all project-level controller tests, kept company-feature tests; `Docs/data/pages/*.md` (no changes); `config/locales/en.yml` (no changes).

---

## 6. Open questions / decisions (consolidated)

> **RESOLVED (2026-06-26, by product owner):**
> - **§6.8 Sessions** — Company-level sessions become **view-only**: keep `index` (+ `show` + artifacts), **remove company-level session creation** entirely (`new` action, `Company/Sessions/New.tsx`, the `:new` route, and any "New session" CTA on the company Sessions index). All session creation lives at the project level. No picker re-scoping needed.
> - **§6.4 Admin** — **KEEP.** Admin is just the generic Administrate model surface, not a company-level screen.
> - **§6.9 Seeds** — **Remove the seed calls** (`Seeds::Semgrep.seed!`, `Seeds::CodeReport.seed!`, company MCP block) and the now-orphaned seed files; update `aixle_builder.rb` prose.
> - **§6.11 Workflow Catalog nav** — **Add** a "Workflow Catalog" entry to the company nav in place of the removed "Shared Library" group.


1. **github_setup relocation URL** — *Decision: keep the same fixed path* `/company/integrations/github_setup` on a slim surviving controller. GitHub App Setup URL is a single global value; the project target rides in `state`. Always redirect to `company_project_integrations_path(project)`.
2. **Stateless (bare company) github_setup hit** — *Recommendation*: treat a stateless install as an error → `company_projects_path` with an alert to install from within a project.
3. **Top-level `api/v1` workflows controller** — *Decision: REMOVE* (controller + nested steps + base + routes 52–60 + tests). Verified company-scoped; project-nested API stays.
4. **Admin (Administrate) dashboards for the 7 entities** — *Recommendation: KEEP.* Scope-agnostic superadmin tools; models persist.
5. **DB migration / data cleanup now vs defer** — *Decision: DEFER.* No destructive/column-dropping migration. Columns are shared with Project rows; existing Company-scoped rows are still read by Sessions and surface in the catalog. Schema/data **untouched** in this PR.
6. **Unused company-only scopes (`for_company`, `visible_for_company`, `company_wide`)** — *Recommendation: KEEP for now.* `belonging_to_company` / `published_in_company` **must** stay.
7. **`Company` model ownership associations** — *Decision: KEEP* (still exercised by Sessions + catalog).
8. **Company-level session creation pickers** — *Decision required (product).* When creating a company-level session, the Tools/Skills/MCP/Repos pickers will be empty (company-scoped rows no longer created). Options: (a) re-scope pickers to the selected project's resources; (b) drop the resource pickers from company-level session creation; (c) leave empty (degraded). Recommendation: (a) or (b).
9. **Company-scoped seed data** — *Recommendation: re-scope, don't delete.* Move Semgrep + Code Report into the seeded demo **project's** scope (or System scope); make Context7 a **System**-scoped MCP server. Update `db/seeds.rb` and refresh `aixle_builder.rb` prose.
10. **`BuilderPage.tsx` company branch** — *Decision: project-only after removal.* Drop `projectId`-null branches and `apiV1Workflow*` imports.
11. **Add Workflow Catalog to company nav?** — *Recommendation: yes* (it is the replacement); currently the sidebar has no catalog link. Confirm with user — slightly out of strict removal scope.

---

## 7. Ordered execution plan

Per project convention, **run Rails inside Docker** (`docker compose exec -T web …`); the host has no gems.

1. **Routes first.** Edit `config/routes.rb`: remove the blocks in §3(a) and add the standalone `github_setup` route (§2). Run `docker compose exec -T web bin/rails routes` and confirm company entity routes are gone, `github_setup` resolves, project + admin + workflow_catalog routes intact.
2. **Relocate the github_setup callback** (§2): create `Web::Company::Integrations::GithubSetupController` (+ slim policy with `github_setup?`), move the action and helpers, repoint redirect fallbacks. Keep the `skip_before_action :dynamic_authorize!`.
3. **Delete web + API controllers** (§3b) and the `app/controllers/api/v1/workflows/` directory. **Delete dead policies** (§3c).
4. **Delete frontend pages** (§3d) — the 7 `pages/Company/*` directories.
5. **Edit navigation & FE references** (§4): `AppSidebar.tsx`, `BuilderPage.tsx`, review `IntegrationsContent.tsx`.
6. **Regenerate `routes.ts`**: `docker compose exec -T web bundle exec rake ts:routes`. Confirm helpers disappear and no FE code imports them: `grep -rn "companyAgentsPath\|companyToolsPath\|companySkillsPath\|companyMCPServersPath\|companyRepositoriesPath\|companyWorkflowsPath\|companyIntegrationsPath\|apiV1Workflow" app/frontend`.
7. **Delete tests** (§3e). Rewrite/move the `github_setup` tests against the relocated controller.
8. **Seeds & prose** (§4 / §6.9): re-scope `Seeds::Semgrep` / `Seeds::CodeReport` / company MCP block; update `aixle_builder.rb` prose.
9. **i18n**: no changes.
10. **Verify build & tests**:
    - Frontend build/typecheck: `docker compose exec -T web bin/vite build` (or project FE build) — must compile with no missing-import/type errors.
    - FE unit tests (Vitest).
    - Backend: `docker compose exec -T web bin/rails test` — no failures referencing removed controllers/routes; `workflow_catalog`, project workflows API, sessions tests pass.
    - Routes sanity: `docker compose exec -T web bin/rails routes | grep -E "integration|workflow|agent|tool|skill|mcp|repositor"`.

---

## 8. Risk & verification checklist

- [ ] **GitHub App callback intact**: `/company/integrations/github_setup` resolves to the relocated controller; project install (`state=project:<id>`) → `company_project_integrations_path(project)`; stateless install → `company_projects_path` + alert. Manually test a project GitHub connect end-to-end.
- [ ] **No dangling route helpers**: regenerated `routes.ts` no longer exports company `*Path` / `apiV1Workflow*`; grep confirms zero FE imports remain.
- [ ] **No broken backend path helpers**: `grep -rn "company_integrations_path\|company_agents_path\|company_tools_path\|company_skills_path\|company_mcp_servers_path\|company_repositories_path\|company_workflows_path\|builder_company_workflow_path" app/` returns nothing outside deleted files. (Catalog uses `builder_company_project_workflow_path` — project-scoped, stays.)
- [ ] **Inertia page resolution**: deleted `Company/*` dirs no longer referenced by any kept controller `render inertia:`.
- [ ] **Models untouched**: 7 models + `company.rb`/`project.rb` associations + `belonging_to_company`/`published_in_company` present, model tests green.
- [ ] **Catalog works**: `WorkflowCatalogController` loads via `Workflow.published_in_company`; duplicate → `builder_company_project_workflow_path`.
- [ ] **Sessions decision applied** (§6.8): pickers re-scoped or removed — not silently empty.
- [ ] **Project parity preserved**: project-level pages + APIs unaffected; shared `*Content.tsx` intact.
- [ ] **Admin intact** (§6.4): admin index/show for the 7 entities still load.
- [ ] **Builder project-only**: `BuilderPage.tsx` renders with a `projectId`; no company-branch references to removed helpers.
- [ ] **Seeds** run clean (`docker compose exec -T web bin/rails db:seed`).
- [ ] **Full build + test suite green**.
- [ ] **Webhooks unaffected**: GitHub/GitLab receivers still process by repository `full_name`.
