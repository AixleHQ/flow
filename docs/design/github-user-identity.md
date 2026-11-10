# Agents act as the user on GitHub

**Task:** #214 · **Status:** proposal · **Date:** 2026-11-10

A user connects their own GitHub account. An agent can then ask for a token that
acts as that user, push commits authored by them, and open the pull request in
their name. The platform provides the mechanism. A workflow's instructions decide
when to use it, as the `github-access` skill and `ALEX_GITHUB_TOKEN` do in this
project today.

## 1. Overview

Today every git action of an agent is the platform's:

| Action | Identity today | Where |
|---|---|---|
| Commit author and committer | `Aixle Flow <noreply@<domain>>` | `GitCredentials::SessionGitSetup.identity_env` |
| Push | GitHub App installation token, narrowed to one repository | `GitCredentials::Vendor#token_for` → `Github::TokenService#generate_installation_token` |
| Pull request | the GitHub App (`aixle-com[bot]`), so a squash merge is authored by the bot | `PullRequests::Github::Provider#client` |

This design adds four things and changes none of the above for a user who does not
use them:

1. **A GitHub connection per user**, made with our GitHub App's user OAuth flow and
   stored as an `OauthCredential` owned by the user. The platform refreshes it.
2. **Two internal tools**, `github_user_token` (the session's current user) and
   `github_user_token_for` (a named user). Each returns a token scoped down to the
   session's GitHub repositories with `contents: write` and `pull_requests: write`,
   plus the identity to commit with.
3. **Consent per project**, two independent switches: "act as me in my tasks" and
   "use my account in tasks that aren't mine".
4. **One rule for "the session's user"**, `Sessions::ActingUser`, used by the new
   tools and by per-user MCP credentials.

## 2. Approach

### 2.1 Connection: reuse the unified OAuth engine

GitHub becomes a static provider in `Oauth::Providers::REGISTRY`, next to Sentry
and Railway. The connect flow is the existing `Web::OauthController#authorize` /
`#callback` with `owner_type: "User"`. The token lands in `OauthCredential`
(`owner: user, provider: "github", mcp_server: nil`). This reuses, unchanged:

- `Oauth::State`: signed, single-use, user-pinned state with a server-side PKCE verifier;
- `resolve_owner` / `may_connect?`: a `User` owner resolves only to `current_user`;
- encryption (`oauth_key`), `RefreshLease`, `Oauth::TokenService#fresh`;
- the 5-minute sweep `Oauth::RefreshExpiringTokensActivity`, which already iterates
  every `refresh_due` row whatever its owner or provider;
- `OauthCredential#mark_refresh_error!` and the `OauthMailer.refresh_failed` email for
  User owners.

GitLab, Bitbucket and Azure DevOps later become further registry entries with their
own `provider` value. The consent table (§3.1) carries `provider` for the same reason.
Nothing in this design is GitHub-specific above the provider entry, the
`Github::UserTokenService` adapter and the two tools.

**Alternatives considered**

- *A dedicated `github_user_connections` table.* It duplicates encryption, the refresh
  lease, the sweep and the failure email that `OauthCredential` already has. Rejected.
- *Extending `Github::InstallationOwnership` / `GithubSetupController`.* That callback
  belongs to the install flow, is project-scoped and discards the token on purpose.
  Mixing a user-level connection into it would change the install flow. Rejected.
- *A personal access token pasted by the user.* Ruled out by the task: the platform
  cannot narrow it, and a person rotates it by hand.

### 2.2 Tokens: scope down at issue time, never hand out the user's own token

The stored user token never leaves the server. Each tool call mints a new token
with `POST /applications/{client_id}/token/scoped` (Basic auth with the App's
`client_id` / `client_secret`), confirmed against GitHub's OpenAPI description:

```json
{ "access_token": "<stored user token>",
  "target": "<owner login>",
  "repositories": ["repo-a", "repo-b"],
  "permissions": { "contents": "write", "pull_requests": "write" } }
```

The response is an `authorization` object with `token` and `expires_at`. An invalid
`access_token` answers 404. The token's access is the intersection of the App's
installation, the user's own access and the requested scope, so it cannot reach
another repository or another permission.

**One token per repository owner.** `target` names one user or organization, so the
scoped endpoint cannot cover repositories of two owners in one token. The tool groups
the session's GitHub repositories by `Repository#owner_name` and mints one token per
group. Most sessions have one owner and get one token.

**Alternatives considered**

- *Route the user's token through the existing git credential helper and `gh`
  wrapper*, by switching `GitCredentials::Vendor` per session. That would put "which
  actions run as the user" in the platform, which the task assigns to a workflow's
  instructions. Rejected for this task. It remains possible later as an opt-in on top
  of the same service.
- *Return the stored user token.* It would carry every repository and permission the
  App and the user share. Rejected.

### 2.3 Masking: the issued token becomes a session secret

`Sessions::SecretRegistry` (the container's `redact.list`) and
`Sessions::SecretRedactor` (collected and served logs) read their values only from
config items today. Every issued token is recorded in a new table,
`user_token_issuances` (§3.2), with its value encrypted. Both classes add those
values to their lists. The tool follows `InternalTools::GetConfigItem`'s order:
record the row, arm `redact.list` with `SecretRegistry.publish!`, and only then
return the token. If arming fails, the tool refuses.

The value is kept, not only a hash, because served logs are redacted when they are
read (`LiveLogReader`, `LogTail`, the API log tail), long after the call.

### 2.4 One rule for the session's user

`Sessions::ActingUser.for(session)` returns the user and the source of the decision:

1. `session.step_run&.workflow_run&.board_task&.assignee`, read when called: `:task_assignee`;
2. otherwise `session.step_run&.workflow_run&.user`, the run's owner: `:run_starter`;
3. otherwise `session.user`, the person who started a standalone session: `:session_user`;
4. otherwise `nil`.

It returns the user only. Membership and consent are checked by the callers that
need them (§4.3).

**Every place that decides "the session's user" today, and what changes:**

| Place | Today | After |
|---|---|---|
| `SessionContextService#inject_oauth_token!` (per-user MCP token) | `session.user` | `ActingUser.for(session)` (decision D1) |
| `SessionService#refresh_oauth_tokens_for_session` (workflow-step pre-start refresh) | `session.user` | `ActingUser.for(session)` (D1) |
| `Oauth::Preflight.missing_connections(servers, user:)` and `SessionService#preflight_oauth!` (interactive launch) | the launching user | unchanged: an interactive launch has no task, so rule 3 returns the same user |
| `github_user_token` | n/a | `ActingUser.for(session)` |
| `TaskService.run_owner_for` (who owns a run: the assignee if they can own runs, otherwise the requester) | unchanged | unchanged. It decides whose agent credential runs the session and who pays, which is a different question |
| `SessionService#preflight_agent_credential!(workflow_run.user)` | unchanged | unchanged, for the same reason |
| `ConfigItemAccess.record!(user: session.user)` | unchanged | unchanged: an audit of whom the session ran for |

**D1: this changes whose per-user MCP credential a session uses in one case.**
`session.user` is the run owner, which `TaskService.run_owner_for` already sets to
the assignee when the assignee can own runs. The two rules differ only when a task
has an assignee who is not the run owner:

- the assignee cannot own runs (a viewer, an inactive member, or no agent credential
  in the company), so the person who moved the card became the owner; or
- the task was reassigned after the run started.

In those cases the MCP token would switch from the run owner's to the assignee's,
and a session whose assignee has not connected that MCP server would stop at
`Oauth::ReauthRequired` where it runs today. **This is a decision for Alex.** The
design recommends unifying (one rule, as the task asks). The alternative keeps MCP
on `session.user` and uses `ActingUser` only for the new tools. Either choice is one
line in each of the two MCP call sites. Implementation step 4 is written for the
recommendation and is the only step that changes if Alex chooses otherwise.

## 3. Data model changes

### 3.1 `act_as_consents` (new)

| Column | Type | Notes |
|---|---|---|
| `user_id` | bigint, FK users, not null | |
| `project_id` | bigint, not null | composite FK `(project_id, company_id)` → `projects (id, company_id)`, as in `CreateRunners` |
| `company_id` | bigint, FK companies, not null | |
| `provider` | string, not null | `enumerize :provider, in: %w[github]` |
| `in_own_tasks` | boolean, not null, default false | the current-user tool |
| `in_others_tasks` | boolean, not null, default false | the any-user tool |
| timestamps | | |

Unique index on `(user_id, project_id, provider)`. A missing row means both switches
are off. Model `ActAsConsent` (`belongs_to :user, :project, :company`), with
`ActAsConsent.allows?(user:, project:, provider:, scope: :own | :others)`. The row
is never referenced by id from another row, so it needs no `TenantScope.owned` rule.
`project` and `company` must agree, which the composite key enforces.

### 3.2 `user_token_issuances` (new)

An audit row for every token handed out, and the masking source.

| Column | Type | Notes |
|---|---|---|
| `terminal_session_id` | bigint, FK, not null | |
| `company_id`, `project_id` | bigint, not null | composite FK as above |
| `acting_for_user_id` | bigint, FK users, not null | whose identity the token carries |
| `session_user_id` | bigint, FK users, null | `session.user` at the time of the call |
| `tool_name` | string, not null | `github_user_token` or `github_user_token_for` |
| `provider` | string, not null | `github` |
| `oauth_credential_id` | bigint, FK, null, `on_delete: :nullify` | survives a disconnect |
| `encrypted_token` | text, not null | `Encryptable`, `encryption_key :oauth_key`, accessor `token=` / `token` |
| `token_last_eight` | string | from the response, for support |
| `target_login` | string, not null | the owner the token is scoped to |
| `repository_full_names` | string[], not null | |
| `expires_at` | datetime | |
| `created_at` | datetime | no `updated_at`: rows are immutable |

Index on `terminal_session_id`, and on `(acting_for_user_id, created_at)` for a later
"recent use" list. The issuance row stores the scoped token, not the user token.

### 3.3 `oauth_credentials` (no migration)

A GitHub connection is a row with `owner_type: "User"`, `provider: "github"`,
`mcp_server_id: NULL` and `oauth_client` = the static GitHub client. The existing
unique index `(owner_type, owner_id, oauth_client_id, provider, mcp_server_id)`,
with `nulls_not_distinct`, already gives one connection per user. The identity goes
in `metadata["github_user"] = { "id", "login", "name", "fetched_at" }`.

## 4. API / interface changes

### 4.1 OAuth provider entry

```ruby
"github" => {
  issuer: "https://github.com",
  authorization_endpoint: "https://github.com/login/oauth/authorize",
  token_endpoint: "https://github.com/login/oauth/access_token",
  scopes: "",            # GitHub Apps take permissions from the App, not scopes
  settings_key: :github, # reads the existing Settings.github.client_id / client_secret
  after_connect: "Github::UserConnection"
}
```

`after_connect` is a new, optional registry key. `Web::OauthController#callback`
calls `Oauth::Providers.after_connect(provider, credential)` after
`upsert_from_token!`. For GitHub that runs `Github::UserConnection.record_identity!`
(`GET /user` with the new token, stored in `metadata["github_user"]`). If that
call fails, the callback destroys the new row and shows "Failed to complete
connection", so a connection never exists without an identity.

No new environment variable. `GITHUB_APP_CLIENT_ID` and `GITHUB_APP_CLIENT_SECRET`
already exist. The comment above them in `config/settings.yml` changes to say they
are also required for user connections.

### 4.2 Web routes (profile)

| Route | Action | Purpose |
|---|---|---|
| `GET /profile/connections` | `ProfileController#connections` | Inertia page `Profile/Connections` |
| `DELETE /profile/connections/:provider` | `ProfileController#disconnect` | disconnect |
| `PATCH /profile/act_as_consents` | `ProfileController#update_act_as_consent` | body `{ projectId, provider, inOwnTasks?, inOthersTasks? }` |
| `POST /oauth/github/authorize` | existing `Web::OauthController#authorize` | `owner_type=User&owner_id=<me>&return_to=/profile/connections` |

These are `member` routes on `resource :profile`, like `update_mcp_tools`.
`update_act_as_consent` resolves the project with `Project.for_user(current_user)`
inside `current_company`, and answers 404 when the project is not found there.

**Disconnect** does three things:

1. It revokes the grant at GitHub (`DELETE /applications/{client_id}/grant`). This is
   best effort: a failure is logged, and disconnect continues.
2. It destroys the `OauthCredential` row.
3. It deletes the user's `act_as_consents` rows for `github`.

Issuance rows stay, with `oauth_credential_id` nulled.

Page props, through Alba resources:

- `UserConnectionResource`: `provider`, `status` (`connected` | `needs_reconnect`, the
  latter when the row is in `error` or `revoked`), `login`, `name`, `avatarUrl`,
  `connectedAt`.
- `ActAsConsentResource` for each project of `current_company` visible to the user:
  `projectId`, `projectName`, `inOwnTasks`, `inOthersTasks`.
- `available`: whether `Settings.github.client_id` and `client_secret` are both set.

### 4.3 Internal tools

Both tools live in `app/services/internal_tools/` and are built with
`Tools::DefinitionDSL`:

```ruby
tags :github_identity            # new TagCatalog entry, label "GitHub as a user", ui_visible: true
requires_integration :github
availability ->(_ctx) { Github::UserConnection.configured? }
unavailable_message "Connecting GitHub accounts is not configured on this installation."
read_only true; destructive false; idempotent false; open_world true
```

They are `user_attachable` (the default) and have no `inject_when`. The tool appears
only where whoever configures a step, a workflow or a session adds it. That is how
the task's "whoever configures a workflow or a session decides which tool the agent
gets" is met.

| Tool | Params | User | Consent checked |
|---|---|---|---|
| `github_user_token` | none | `Sessions::ActingUser.for(session)` | `in_own_tasks` |
| `github_user_token_for` | `user_id` (integer, required; from `board_list_members` or a task's `assignee_id`) | that user | `in_own_tasks` if the user is `ActingUser.for(session)`, otherwise `in_others_tasks` |

Shared logic goes in `InternalTools::Concerns::GithubUserTokenContext`. The steps
below run in order, and the first failure answers with an `error(...)`:

1. **Resolve the user.** If there is none, the error is: "No user to act as: this
   session has no task assignee and no user who started it."
2. **Check the user.**
   - They must be `User.authenticatable`.
   - They must have an active membership in `session.company`.
   - The session's project must be in `Project.for_user(user)`.

   Otherwise the error is: "<name> is not a member of project <project>."
3. **Check the connection.** It must be an `OauthCredential` for `(user, "github")`
   that is not revoked. Otherwise the error is: "<name> has not connected a GitHub
   account. They can connect one under Profile → Connected accounts."
4. **Check consent.** `ActAsConsent.allows?`, otherwise one of:
   - "<name> has not allowed agents to act as them in their own tasks in project <project>.";
   - "<name> has not allowed their GitHub account to be used in tasks that aren't theirs in project <project>."
5. **Collect the repositories.** These are the session's repositories whose
   integration is GitHub, active and `github_app?`. If there are none, the error is:
   "This session has no GitHub repositories connected through the GitHub App." A
   repository on a PAT connection is listed in `skipped` with a reason, because the
   App is not installed there.
6. **Get a fresh user token.** Call `Oauth::TokenService.refresh_if_expiring_soon(cred)`
   (refresh if less than 1 hour is left), then
   `access_token_for(owner: user, provider: "github")`. `ReauthRequired` gives the
   error: "<name>'s GitHub connection needs to be renewed under Profile → Connected
   accounts."
7. **Mint the tokens.** Call `Github::UserTokenService#scoped_token` once per owner
   group. A 404 marks the credential `error` through `mark_refresh_error!`, which
   sends the existing email, and gives the reconnect error. A 422 gives "GitHub refused
   access to <owner>/<repos> for <login>: the user or the App has no access there."
8. **Record and arm.** Write one `UserTokenIssuance` row per token, then
   `Sessions::SecretRegistry.publish!(session)`. If arming fails, the tool refuses,
   like `GetConfigItem`.
9. **Return the result:**

```json
{
  "user": { "id": 82, "name": "Artem" },
  "identity": { "login": "artem", "github_id": 123, "name": "Artem",
                "email": "123+artem@users.noreply.github.com" },
  "tokens": [
    { "token": "ghu_…", "owner": "AixleHQ", "repositories": ["AixleHQ/flow"],
      "permissions": { "contents": "write", "pull_requests": "write" },
      "expires_at": "2026-11-10T20:00:00Z" }
  ],
  "skipped": [],
  "note": "Use the token only in the command that needs it. Do not echo it, write it to a file, or paste it anywhere. Ask again when it expires."
}
```

`identity.name` falls back to `login` when the GitHub profile has no name. Error
messages never include a token or a GitHub response body: `InternalToolExecutor`
passes exception messages to the agent.

### 4.4 `Github::UserTokenService` (new adapter)

`app/services/github/user_token_service.rb` is the app-owned adapter for the GitHub
calls. It uses Octokit with `client_id` / `client_secret` Basic auth for the
`/applications/...` endpoints, the same way the existing services do:

- `scoped_token(user_token:, target:, repositories:, permissions:)` returns `{ token, expires_at, token_last_eight }`;
- `user(user_token)` (`GET /user`) returns `{ id, login, name, avatar_url }`;
- `revoke_grant(user_token)` (`DELETE /applications/{client_id}/grant`).

Errors map to `Github::UserTokenService::InvalidToken` (404),
`::Forbidden` (403/422) and `::Unavailable` (5xx). A canonical fake,
`FakeGithub::UserTokenService`, goes in `test/support/fakes/fake_github_service.rb`.

`Github::UserConnection` holds the domain side: `configured?`, `record_identity!`,
`identity_for(credential)` (re-fetches `GET /user` when `fetched_at` is more than
24 hours old) and `disconnect!(user)`.

### 4.5 GitHub webhook

`Webhooks::GithubController#receive` gains `when "github_app_authorization"`. With
`action == "revoked"`, every `OauthCredential` with `provider: "github"` and
`metadata->'github_user'->>'id' = sender.id` gets `status: :revoked` and its tokens
cleared. GitHub sends this event to every App without a subscription.

### 4.6 Token endpoint quirk (generic fix)

GitHub's token endpoint answers a bad code or a bad refresh token with **HTTP 200**
and `{"error": "bad_refresh_token", ...}`. Today `Oauth::TokenService#perform_refresh!`
and `Web::OauthController#exchange_code!` treat any 2xx as success. With such a
response `apply_token_response!` would store a blank access token and mark the row
`active`. Both must raise when `error` is present or `access_token` is blank,
without putting the body in the message. A standards-compliant server answers 400
here, so other providers are not affected.

## 5. Implementation steps

1. **Provider and connection** (backend only).
   - Add the `github` entry and the `after_connect` hook to `Oauth::Providers`, and
     call the hook in `Web::OauthController#callback`.
   - Make the §4.6 fix in `perform_refresh!` and `exchange_code!`.
   - Add `Github::UserTokenService` with its fake and contract tests.
   - Add `Github::UserConnection`.
   - Update the `config/settings.yml` comment.
2. **Consent and issuance tables.**
   - Write the migrations for `act_as_consents` and `user_token_issuances`, with
     composite keys as in `CreateRunners`.
   - Add the models `ActAsConsent` and `UserTokenIssuance` (encryption as in
     `OauthCredential`) and their factories.
3. **Masking.**
   - `Sessions::SecretRegistry#values`: union the issuance tokens for the session.
   - `Sessions::SecretRedactor.secret_values_for`: union them too. The early
     `return [] if ids.blank?` must not skip the issuances.
4. **`Sessions::ActingUser`** in `app/services/sessions/acting_user.rb`. Switch
   `SessionContextService#inject_oauth_token!` and
   `SessionService#refresh_oauth_tokens_for_session` to it (D1).
5. **Tools.**
   - Add `InternalTools::GithubUserToken`, `InternalTools::GithubUserTokenFor` and
     the `GithubUserTokenContext` concern.
   - Add the `:github_identity` entry to `Tools::TagCatalog`.
6. **Profile UI.**
   - Add the `connections`, `disconnect` and `update_act_as_consent` actions and their
     routes, and the resources (run `rails typelizer:generate`).
   - Add `pages/Profile/ConnectionsPage.tsx` with a "Connected accounts" tab in
     `ProfileTabs`:
     - a GitHub card with Connect, Disconnect (confirmation modal) and Reconnect when
       `needs_reconnect`;
     - a table of projects with two Mantine `Switch`es per row, saved on change
       through `apiFetch` followed by `router.reload({ only: ['consents'] })`;
     - when `available` is false, a note that the installation has not configured it.
7. **Webhook.** Handle `github_app_authorization` (§4.5).
8. **Docs.** Edit `docs/user-guide/github.md` and its mirror
   `app/frontend/pages/Docs/data/pages/github.md`:
   - a new section, "Acting as yourself", covering connecting, the two consents, the
     two tools, the errors, and the example below;
   - under "Self-hosted: the GitHub App", the extra callback URL `/oauth/callback`, which
     goes after the existing one (see R3), and "Expire user authorization tokens" on;
   - in "Tools", the two new rows.

   Also add a `CHANGELOG.md` entry under `### Added` with the **Integrations** area
   from `docs/product/changelog-product-areas.md`.

The docs example of instructions that commit and open a PR as the user:

```bash
# token, email, name come from github_user_token
export GIT_AUTHOR_NAME="$NAME" GIT_AUTHOR_EMAIL="$EMAIL" \
       GIT_COMMITTER_NAME="$NAME" GIT_COMMITTER_EMAIL="$EMAIL"
git commit -s -m "feat: ..."
git -c credential.helper= \
    -c credential.helper='!f() { echo username=x-access-token; echo "password=$TOKEN"; }; f' \
    push origin HEAD:feature/x
GH_TOKEN="$TOKEN" gh pr create -R owner/repo --base develop --head feature/x --title "..." --body "..."
```

Steps 1–3 can be merged on their own, because nothing calls them yet. Steps 4 and 5
need 1–3. Step 6 needs 1–2.

## 6. Testing approach

These tests follow `docs/testing.md`: real database, app-owned seams, and WebMock only
in adapter contract tests.

- **Adapter:** `test/services/github/user_token_service_test.rb` has WebMock contract
  tests for scoped tokens (200, 404, 422, 5xx), `GET /user` and grant revocation. The
  realistic payloads also pin `FakeGithub::UserTokenService` (R4).
- **OAuth:**
  - `test/services/oauth/token_service_test.rb` gets a 200 response with `error`,
    which must not activate the row and must count a refresh failure.
  - The callback request test (`test/integration/web/oauth_*`) covers a GitHub
    connect for a `User` owner, stores `metadata["github_user"]`, refuses another
    user's `owner_id`, and on a failed identity fetch leaves no row behind.
- **Models:** `ActAsConsent` (defaults, uniqueness, `allows?`, the project and
  company agreement) and `UserTokenIssuance` (encryption round trip; the token is
  never in `inspect` or `attributes`).
- **`Sessions::ActingUser`:** the four outcomes, and a reassigned task (the live read).
- **Tools** (`test/services/internal_tools/github_user_token_test.rb` and
  `github_user_token_for_test.rb`, in the shape of `get_config_item_test.rb`):
  - every error in §4.3, and the consent matrix (own versus others, the named user
    being the acting user);
  - several owners giving several tokens, and PAT repositories in `skipped`;
  - a refusal when `SecretRegistry.publish!` fails;
  - the issuance row is written, and the token appears in `SecretRegistry#values` and
    `SecretRedactor.secret_values_for`;
  - no token in any error.
- **Masking:** `secret_registry_test.rb` and `secret_redactor_test.rb` cover a session
  with issuances and no secret config items.
- **MCP (D1):** update `session_context_service_test.rb` and the `session_service`
  refresh test so that a task with an assignee who is not the run owner injects the
  assignee's per-user credential.
- **Requests:** `test/integration/web/profile_connections_test.rb` covers the page
  props, a consent update (and 404 for a project outside the company), and disconnect
  (grant revoked through the fake, rows removed, issuances kept).
- **Webhook:** `github_app_authorization` revoked marks the matching credential.
- **Frontend:** `ConnectionsPage.test.tsx` with a typed factory covers the
  connected, not connected, needs-reconnect and unavailable states, and toggling a
  switch calls `apiFetch`.
- **Registry:** `test/services/tools/registry_test.rb` keeps passing (its count is a
  floor). `test/references/aixle_system_reference_test.rb` needs no change.
- **Manual, on staging (acceptance):**
  - connect, then use the token: the push lands as the user, and a push to a
    repository outside the session is refused;
  - the PR is opened as the user, and a squash merge in GitHub's UI is attributed to
    them;
  - the token is masked in the session log and transcript.

## 7. Edge cases & risks

- **R1. Repositories under several owners** need several tokens (§2.2). The tool
  returns a list, so instructions must pick the token for the remote they push to.
  The docs example says so.
- **R2. Scoped token lifetime.** `expires_at` comes from GitHub and is expected to
  equal the parent token's expiry. Refreshing first (step 6 of §4.3) makes it at least
  about an hour, and the tool tells the agent to ask again. A spike on staging
  confirms the value. If it turns out shorter, nothing changes except the docs.
- **R3. Callback URLs on the App.** The user flow redirects to `/oauth/callback`. The
  App must list it as a callback URL, and the existing
  `/company/integrations/github_setup` must stay first, because install-time user
  authorization goes to the first URL. If an operator puts them in the wrong order,
  installing breaks. The docs and the staging checklist cover this. On aixle.com
  this is a one-time App settings change before release.
- **R4. Refresh-token rotation.** GitHub refresh tokens are single use. `RefreshLease`
  and the "only mark an error if the stored refresh token was the one sent" rule in
  `refresh_leased!` already handle concurrent refreshes.
- **R5. Long-lived grants.** The sweep refreshes every connection about every 8 hours
  for as long as it exists, so an unused connection stays alive. That is what
  "the platform refreshes the token" means. Disconnect, or a revocation on GitHub
  (§4.5), ends it. A suspended user's row is skipped by `with_authenticatable_owner`
  and lapses.
- **R6. Tokens in the model's context** were accepted by Alex. Masking covers the
  `redact.list` filters, the collected terminal output and transcripts, and served
  logs. A value the agent transforms (base64, split) is not masked. That limit also
  applies to config-item secrets today.
- **R7. Live assignee.** `ActingUser` reads the assignee at call time. After a
  reassignment mid-session, the MCP token injected at start stays the old user's,
  while a later tool call returns the new assignee's.
- **R8. The user's own access.** A scoped token is created even where the user can
  only read. The push then fails at GitHub with a 403, which the agent sees in git's
  output. The design does not pre-check permissions per repository.
- **R9. Same GitHub account for two Flow users.** This is allowed. Each proved control
  of it through GitHub's consent. A revocation webhook marks both rows.
- **R10. Encrypted scoped tokens at rest** in `user_token_issuances` live at most a few
  hours. They are kept because masking at read time needs them.

## 8. Decisions & assumptions

| # | Decision | Source |
|---|---|---|
| D1 | `ActingUser` also governs per-user MCP credentials. This changes behaviour only when a task's assignee is not the run owner (§2.4). **For Alex to confirm.** | Task: "If unifying would change whose MCP credential a session uses today, the design names that as a decision for Alex" |
| D2 | "The user who started the run" is `workflow_run.user`. For a run started by a trigger, that is the binding's run-as user (`WorkflowTriggers::RunAs`, `created_by`). There is no other "started by" record. | `WorkflowRun belongs_to :user`, `TriggerEngine.fire_workflow(actor:)`. **Reviewer to confirm.** |
| D3 | The task's assignee wins even when they cannot own runs. The agent credential and billing stay with the run owner (`run_owner_for`). | Task §4 ("the assignee of the session's board task"), and the existing `run_owner_for` |
| D4 | `github_user_token_for` for the session's own acting user checks "in my tasks". Any other user needs "in tasks that aren't mine". | Task §3: "their own tasks" versus "tasks that aren't theirs" |
| D5 | Consent applies to sessions in that project, whether or not the session has a task. A no-task session counts as "own" only for the user `ActingUser` returns. | Task §3 and §4 |
| D6 | The connection is user-level, one GitHub account per Flow user across companies. Consent is per project. The profile page lists the projects of the current company. | Task §1 ("in the user's own settings"); the profile pages render in the current company |
| D7 | Disconnect revokes the grant at GitHub and deletes the user's GitHub consents. Reconnecting starts with both switches off. A reconnect from `needs_reconnect` (no disconnect) keeps them. | Least privilege. **Reviewer to confirm.** |
| D8 | The tools are `user_attachable` with no auto-injection. They appear in the picker under "GitHub as a user". | Task §2: "whoever configures a workflow or a session decides which tool the agent gets" |
| D9 | Only repositories on a GitHub **App** connection are covered. PAT-connected repositories are skipped with a reason. | The scoped endpoint needs the App installed on the target |
| D10 | `user_id` is the only way to name a user. | Board tools expose member ids (`board_list_members`, `assignee_id`) |
| D11 | No new environment variable. The existing `GITHUB_APP_CLIENT_ID` / `SECRET` gate the feature. | `config/settings.yml` `github.*` |
| D12 | The platform does not set the commit identity, sign-off or `gh` credentials for the session. It returns the identity, and the instructions apply it. | Task: "a workflow's instructions decide how to use it" |

## 9. Deferred questions

- **Revoking issued tokens when a session ends** (`DELETE /applications/{client_id}/token`).
  They expire on their own within hours. Whether revoking a scoped token leaves its
  parent intact is unverified, so this waits for a spike.
- **A "recent use" list on the profile**, showing which sessions took my token. The
  issuance table and its index support it. The task does not ask for it.
- **Notifying a user when the any-user tool takes their token.** Not asked for.
- **Routing the user's token through the git credential helper and `gh` wrapper**
  (§2.2), so that agents need no token in context. This is a later opt-in.
- **GitLab, Bitbucket and Azure DevOps providers.** Out of scope. They need a
  registry entry, an adapter and a tool pair each.
- **Moving this project's workflows from `ALEX_GITHUB_TOKEN` to the tools.** This
  follows after release (task: out of scope).
