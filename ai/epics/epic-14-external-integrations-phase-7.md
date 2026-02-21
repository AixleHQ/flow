# Epic 14: External Integrations (Phase 7)

> **Sprint-status tracking:** `epic-14` (numbering shifted due to Container Runtime epic insertion)

System integrates with external development services (GitHub, Linear) to enable seamless code management and task tracking within agent workflows.

**FRs covered:** FR66, FR67, FR68, FR69, FR70, FR71, FR72

**Phase:** 7 (Depends on: Epic 10 Sessions, Epic 11 Artifacts)

**Related:** Epic 15 (Monaco + VS Code Server) — when VS Code Server is deployed, cloned repositories (Story 14.3) are browsable and editable in a full IDE instead of the read-only file viewer. Story 14.4 (Create PR) benefits from VS Code's built-in git UI.

**User Outcome:** Users can connect GitHub repositories for code context in agent sessions, create PRs from session output, and manage Linear tasks through agents.

---

## GitHub Integration

### Story 14.1: Integration Model + GitHub App Credentials

**As an** admin,
**I want to** connect a GitHub App to my company,
**so that** the platform can access GitHub repositories on behalf of the organization.

**Acceptance Criteria:**

1. **Integration model** — `belongs_to :company`. Fields: `provider` (enumerize: github, linear), `name` (string, e.g. org name), `credentials` (encrypted jsonb), `settings` (jsonb), `status` (enumerize: active, inactive, error), `connected_by_id` (User). Multiple integrations per provider per company allowed (e.g. service company with multiple client GitHub orgs).
2. **Platform-level GitHub App config** — `app_id` and `private_key` are platform-wide settings (Settings/env), NOT per-integration. These are the same for all companies — one GitHub App for the entire platform. Integration stores only `installation_id` (per GitHub org where App is installed).
3. **Setup URL flow** — Admin clicks "Connect GitHub" → redirected to GitHub App installation page → installs App on their org (selects repos) → GitHub redirects back with `installation_id` → system creates Integration automatically. Name auto-populated from org name via `GET /app/installations/{id}` → `account.login`.
4. **Connection test** — On creation, system generates JWT from platform app_id + private_key, exchanges for installation access token, verifies access. Sets status to `active` or `error`.
5. **API endpoints** — `Api::V1::Company::IntegrationsController` — index, create (from callback), show, destroy. Scoped to company admin.
6. **Serializer** — Returns name, provider, status, settings, connected_by, connected_at, repos_count. Never returns credentials.
7. **UI** — Company Settings → Integrations tab. List of connected integrations with org name, status, repo count. "Connect GitHub" button triggers setup flow. "Connect Linear" button triggers OAuth flow.

**Dev Notes:**
- GitHub App auth flow: `platform app_id + private_key → JWT (RS256, 10min TTL) → POST /app/installations/{installation_id}/access_tokens → installation_token (1h TTL)`
- **Token lifecycle**: installation access token lives 1 hour, but is generated on-the-fly for each operation (clone, PR). Never cached or stored. `app_id + private_key` (permanent) are the real credentials.
- Gem: `jwt` for JWT generation, `octokit` for GitHub API
- Multiple GitHub integrations per company: service companies (e.g. agency) may connect multiple client GitHub orgs. Each Integration = one GitHub org installation.
- GitHub App registered once by platform owner as public ("Any account" install option), `setup_url` points to callback endpoint

---

### Story 14.2: Repository Model + CRUD

**As a** user,
**I want to** add GitHub repositories to my company or project,
**so that** they can be used as code context in agent sessions.

**Acceptance Criteria:**

1. **Repository model** — polymorphic `belongs_to :scope` (Company | Project), same pattern as Asset/Agent/Tool. Fields: `integration_id`, `full_name` ("owner/repo"), `default_branch`, `clone_url`, `is_private` (boolean), `description`, `last_fetched_at` (datetime).
2. **List available repos** — API endpoint that queries GitHub API (`GET /installation/repositories`) for a given `integration_id` and returns repos available to that installation. User selects from this list.
3. **Add repository** — User selects integration (if multiple), selects repo from available list, chooses scope (company or project), optionally overrides default branch. System validates repo exists and is accessible.
4. **CRUD endpoints** — `Api::V1::Company::RepositoriesController` and `Api::V1::Company::Projects::RepositoriesController`. Index (with merged_for_project pattern), create, show, destroy.
5. **Merged query** — `Repository.merged_for_project(project)` returns company + project repos with `scope_indicator`, same pattern as Asset/Tool/Skill.
6. **Policies** — Pundit: admin for company-level, project_accessible for project-level.
7. **UI** — Repository list in Company Settings and Project Settings tabs. Add dialog with repo picker (searchable list from GitHub API). Shows repo name, branch, private/public badge, scope indicator.

**Dev Notes:**
- Follow exact same polymorphic scope pattern as `Skill` model
- `full_name` is unique within scope (no duplicate repos in same company/project)
- `clone_url` stored as HTTPS format: `https://github.com/{full_name}.git`

---

### Story 14.3: Repository Clone at Session Injection

**As a** user,
**I want** configured repositories to be automatically cloned into my agent session container,
**so that** the agent has access to fresh code context.

**Acceptance Criteria:**

1. **Session config extension** — `session_config` (jsonb on AgentSession) accepts `repository_ids: [...]` — list of repositories to inject.
2. **SessionContextService extension** — New step in context assembly: for each selected repository, generate a fresh installation access token and perform shallow clone into container.
3. **Shallow clone** — `git clone --depth=1 --branch={default_branch} https://x-access-token:{token}@github.com/{full_name}.git {workspace}/repos/{repo_name}` — minimal history, always fresh.
4. **Multiple repos** — Support cloning multiple repositories into separate subdirectories under `/workspace/repos/`.
5. **Clone failure handling** — If clone fails (auth error, repo not found, network), log error and continue session start. Report failed repos in session metadata, don't block session.
6. **Context file mention** — Injected CLI context files (CLAUDE.md, AGENTS.md, etc.) include a section listing cloned repositories and their paths.
7. **Session Launch UI** — Repository picker in New Session form. Shows available repos (merged company + project). Multi-select.

**Dev Notes:**
- **Token lifecycle**: generate fresh installation access token immediately before clone. Token lives 1h but clone takes seconds. One token per integration (not per repo) — if cloning 3 repos from same org, reuse the same token. Different orgs = different tokens.
- Clone happens inside container via `docker exec` or as part of container preparation in Temporal workflow
- Repo path convention: `/workspace/repos/{repo_name}` (last segment of full_name)
- Update `last_fetched_at` on Repository after successful clone
- Repos from different integrations (orgs) work transparently — each repo knows its `integration_id`, system resolves the right credentials

---

### Story 14.4: Create PR from Session

**As a** user,
**I want** the agent to create a Pull Request from changes made during a session,
**so that** code changes can be reviewed and merged through normal Git workflow.

**Acceptance Criteria:**

1. **Internal Tool** — New tool `github_create_pr` (kind: internal). Input schema: `{ repository_id, title, body, head_branch, base_branch (optional, defaults to repo default_branch) }`.
2. **Tool execution** — Temporal activity: generates installation access token → creates branch via GitHub API (or pushes from container) → creates PR via `POST /repos/{owner}/{repo}/pulls`.
3. **PR metadata** — Returns PR URL, number, state. Saved in session metadata (`session.metadata[:pull_requests] << { repo, pr_url, pr_number }`).
4. **Branch strategy** — Agent creates a new branch in the cloned repo, commits changes, pushes. Branch name convention: `session/{session_id}/{descriptive-name}`.
5. **Push permissions** — The installation access token (with Contents: write permission) is used for push. Token injected as git credential in container.
6. **Error handling** — If PR creation fails (branch exists, no changes, auth error), return structured error to agent.
7. **Session UI** — PR links displayed in session details (clickable links to GitHub).

**Dev Notes:**
- This is an internal Tool, follows existing Tool execution pattern via Temporal
- Agent in container needs git configured: `git config user.name` and `user.email` from session context
- Two approaches for push: (a) agent pushes from container using token, (b) Temporal activity copies changes and pushes. Prefer (a) — simpler, agent already has the context
- Inject git credentials into container: `git credential store` or env `GIT_ASKPASS`

---

## Linear Integration

### Story 14.5: Linear OAuth + Integration

**As an** admin,
**I want to** connect my Linear workspace to the platform,
**so that** agents can interact with Linear tasks.

**Acceptance Criteria:**

1. **Linear OAuth flow** — Standard OAuth 2.0: redirect to Linear → authorize → callback with code → exchange for access token. Scopes: `read`, `write`, `issues:create`.
2. **Integration record** — Reuses Integration model (provider: `linear`). Credentials: `{ access_token, token_type, expires_at }`. Settings: `{ workspace_id, workspace_name }`.
3. **Callback endpoint** — `Api::V1::Company::Integrations::LinearCallbackController` — handles OAuth callback, exchanges code for token, saves Integration.
4. **Connection test** — After token exchange, query `viewer { id name }` via Linear GraphQL API. Store workspace info in settings.
5. **Token refresh** — Linear tokens don't expire by default (API keys) or use refresh tokens (OAuth). Handle both modes.
6. **UI** — "Connect Linear" button on Integrations page → redirects to Linear OAuth → returns to app with connected status.

**Dev Notes:**
- Linear GraphQL API endpoint: `https://api.linear.app/graphql`
- Linear OAuth docs: `https://developers.linear.app/docs/oauth/authentication`
- One Linear integration per company (same as GitHub)

---

### Story 14.6: Linear Tasks Read

**As a** user,
**I want** agents to be able to read Linear tasks,
**so that** agents have context about current work and priorities.

**Acceptance Criteria:**

1. **Internal Tool** — New tool `linear_list_issues` (kind: internal). Input schema: `{ team_id (optional), state_name (optional), assignee_id (optional), limit (default: 50) }`.
2. **GraphQL query** — Fetches issues with fields: id, identifier, title, description, state { name, type }, assignee { name }, priority, labels, project { name }, estimate.
3. **Filtering** — By team, state, assignee, label, project. Supports pagination (cursor-based).
4. **Response format** — Returns structured list of issues in agent-friendly format.
5. **Teams/States list** — Additional tool `linear_get_workspace_info` returns available teams, workflow states, labels, users — for agent to know what's available.
6. **Caching** — Results cached in Redis (5 min TTL) to avoid excessive API calls. Cache key: `linear:{company_id}:{query_hash}`.

**Dev Notes:**
- Linear uses relay-style pagination with cursors
- Rate limit: 1500 requests/hour — caching is essential
- Tool is available if company has active Linear integration

---

### Story 14.7: Linear Task Actions

**As a** user,
**I want** agents to create and update Linear tasks,
**so that** agents can manage project work autonomously.

**Acceptance Criteria:**

1. **Create issue tool** — `linear_create_issue` (kind: internal). Input: `{ team_id, title, description, state_id (optional), assignee_id (optional), priority (0-4, optional), label_ids (optional), project_id (optional), estimate (optional) }`.
2. **Update issue tool** — `linear_update_issue` (kind: internal). Input: `{ issue_id, state_id (optional), assignee_id (optional), title (optional), description (optional), priority (optional) }`.
3. **Move issue** — Updating `state_id` effectively moves the issue across workflow columns.
4. **Read comments tool** — `linear_list_comments` (kind: internal). Input: `{ issue_id }`. Returns list of comments with body, author, created_at. Sorted chronologically.
5. **Create comment tool** — `linear_create_comment` (kind: internal). Input: `{ issue_id, body }`. Body supports markdown. Returns created comment data.
6. **Validation** — Validate team_id, state_id, assignee_id, issue_id exist before sending to Linear API. Return clear errors if not found.
7. **Response** — Returns created/updated issue or comment data (id, identifier/issue_id, url).
8. **Audit trail** — Tool execution is logged in session history (standard tool execution logging).
9. **Invalidate cache** — After create/update, invalidate relevant Redis cache keys for the company's Linear data.

**Dev Notes:**
- Linear mutations: `issueCreate`, `issueUpdate`, `commentCreate` in GraphQL
- Linear queries: `issue { comments { nodes { body user { name } createdAt } } }`
- Priority values: 0=No priority, 1=Urgent, 2=High, 3=Medium, 4=Low
- All Linear tools share the same integration token resolution: find active Linear integration for session's company

---
