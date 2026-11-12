# Agents act as the user on GitHub

**Task:** #214 · **Status:** proposal, revised after review · **Date:** 2026-11-11

**Revision 3 (2026-11-11).** Alex's second review rejected D13: `TerminalSession`
gets no `attr_readonly :user_id`, and nothing else enforces "set once". The design
describes how `session.user` is set today and that every reader uses it, without a
guard. D13, its sentence in §2.4, its implementation step and its test are removed.
D14 and D15 are accepted.

**Revision 2 (2026-11-10).** Alex's design review accepted §2.1–§2.3, the consent
table, masking and the token-endpoint fix. It replaced the `Sessions::ActingUser`
rule with `session.user` everywhere. §2.4, the tool rules in §4.3, implementation
step 4 and decisions D1–D5 and D7 are rewritten for that, D13–D15 are new, and R7
now describes the attribution change instead of the live assignee read.

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
4. **One current user per session: `session.user`.** It is set once when the session
   is created. The new tools read it, and so do the board and tracker tools, which
   compute their own user today (§2.4).

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

### 2.4 The session's current user is `session.user`

A session has one current user, `session.user`. It is decided once, when the
session is created, and nothing computes it again.

**How it is set today, and stays set.** There are two places that create a session,
and both already set `user` the way the task asks:

| Session | Set in | `session.user` |
|---|---|---|
| Interactive: the terminal, Builder, the API, the personal MCP server | `SessionService.create_and_start` (`user.terminal_sessions.build`) | the user who launched it |
| A workflow step | `SessionService#build_for_workflow_step` (`TerminalSession.create!(user: workflow_run.user)`) | a copy of `workflow_run.user`, chosen when the run starts |

`workflow_run.user` is chosen once per run:

- for a card, by `TaskService.run_owner_for`: the assignee if they can own runs,
  otherwise whoever moved the card or pressed **Run**;
- for a manual run without a card, whoever started it;
- for a trigger, its run-as user (`WorkflowTriggers::RunAs`).

No code changes `terminal_sessions.user_id` after creation today. This design adds
no mechanism to guard that.

**One reader in the tools.** `InternalTools::Base` gets a private `session_user`
that returns `session&.user`. Every internal tool that needs the session's user
calls it. The three copies of `resolve_actor` and the other formulas are deleted.

**Every place that reads the session's user, today's formula, and what changes.**
The first group changes. The rest already read `session.user` and stay as they are.

*Changes: the board, gate, asset and tracker tools*

| Place | Today | After |
|---|---|---|
| `InternalTools::BoardMoveTask` (the actor passed to `TaskService.move`) | `resolve_actor`: `task.assignee \|\| workflow_run&.user` | `session_user` |
| `InternalTools::BoardAddComment` (`author`) | `resolve_actor`, same formula | `session_user` |
| `InternalTools::BoardAttachAsset` (`author`) | `resolve_actor`, same formula | `session_user` |
| `InternalTools::BoardCreateGate` (`creator`) | `workflow_run.user` | `session_user` |
| `InternalTools::PromoteAsset` (`promoter`) | `workflow_run&.user` | `session_user` |
| `InternalTools::TrackerAttachFiles` (`AttachmentExporter user:`) | `workflow_run&.user \|\| session&.user` | `session_user` |
| `InternalTools::TrackerDownloadAttachments` (`AttachmentImporter user:`) | `workflow_run&.user \|\| session&.user` | `session_user` |
| `github_user_token`, `github_user_token_for` | new | `session_user` (§4.3) |
| The comment above `TaskService.run_owner_for` | describes `task.assignee \|\| workflow_run&.user` as the tools' actor | describes `session.user` |

For a step session, `session.user` equals `workflow_run.user`, so the gate, asset and
tracker rows change in code only. The three `resolve_actor` tools change behaviour
(below).

*No change: these already read `session.user`*

| Area | Places |
|---|---|
| Agent credential and billing | `SessionService#preflight_agent_credential!` (launch and revalidation); credential injection in `ContainerStrategies::AgentSessionStrategy`; the Kiro credential write-back (`AgentCredential.from_artifacts(session.user_id, …)` in `AgentSessionStrategy` and `AgentAuthStrategy`); `SessionCompany.membership_for` / `agent_credentials_for` |
| Admission and revalidation | `SessionService` revalidation (`authenticatable?`, `project.accessible_by?`, the active membership); `SessionAdmissionService#pool_configuration` (the per-user pool of a project-less agent login) |
| Per-user MCP tokens and the cloud preflight | `SessionContextService#inject_oauth_token!`; `SessionService#refresh_oauth_tokens_for_session`; `preflight_oauth!` and `preflight_cloud!` |
| Config items | `SessionConfigResolver#user`; `ConfigItemAccess.record!` in `SessionContextService` and `InternalTools::GetConfigItem` |
| Session outputs | asset authors (`created_by`, `uploaded_by`) and the output company (`resolve_output_scope`) in `AgentSessionStrategy` |
| Supervision tools | `InternalTools::Concerns::SessionScope#supervision_owner` |
| Chat | `InternalTools::ChatPostMessage` (`Teams::FileSender user:`) |
| Audit records | `PullRequestContext` and `TrackerContext` operation rows (`user_id: session&.user_id`); `AzureDevopsContext` (`user: session&.user`) |
| BMAD | `BmadMethodInjector` developer name |
| **Found by this revision, not in the review's list** | `InternalTools::ShareAsset` → `PubliclyShareable#share!` (`shared_by: session&.user`); Builder: `Tools::BuilderToolset` (the tools act with `user: session.user`) and `ContextBuilders::AixleBuilder`; `InternalTools::CoderAllocateMachine` (the machine label carries `session.user.email`); `ContainerRuntime::KubernetesRuntime` (the per-user namespace) |
| Who may see or control a session | `Api::V1::Internal::WsAuthController` (owner-only surfaces), `TerminalSessionResource`, `StepRunResource`, `SessionListEntryResource`, `RunListEntryResource`, `PersonalTools::ListSessions`, `PersonalTools::StopSession`, `RecentActivityService`. These answer "whose session is this", and the answer is already `session.user` |

*Not a session's user: these stay on `workflow_run.user`.* `WorkflowService`
(retrying a run, and the board activity for a run's start and end),
`Chat::StatusCard` ("started by") and `PersonalTools::Base` (who may control a run)
read the run's owner. They are about the run, not about one of its sessions, and
`workflow_run.user` is the value every step session copies.

*Found by the step 4 search.* `Trackers::CopyAttachmentsJob` (`AttachmentImporter user: run.user`)
runs from a job with no session, so it reads the run's owner like the readers above.

*No user recorded.* `board_create_task`, `board_update_task` and `board_manage_tags`
record no actor today. They stay that way.

**How this was checked.** A search of `app/` for `session.user`, `session&.user`,
`session.user_id`, `workflow_run.user`, `run.user` and `assignee ||` returns
exactly the rows above. The implementation repeats that search (step 4), and after it
`rg -n "resolve_actor|assignee \|\| workflow_run|workflow_run&?\.user" app/services/internal_tools`
is empty.

**Behaviour changes.**

- **Someone else's card: comment or asset.** An agent's comment or asset on a card
  is authored by the session's user. Today it is authored by that card's assignee.
  The case arises when an agent works on a card other than its own run's card, or
  when the run's card has an assignee who could not own the run.
- **Someone else's card: move.** The move's actor is the session's user.
  `run_owner_for` still picks the next run's owner: the card's assignee if they can
  own runs, otherwise the session's user. Today the actor is the assignee, so an
  assignee who can't own runs became the requester, and so the next run's owner, and
  that run then failed its agent-credential preflight. The board activity row for the
  move also names the session's user.
- **The GitHub tools.** When the session's card's assignee can't own runs, the run's
  owner (the person who moved the card or pressed **Run**) is `session.user`, and the
  tools act as them.
- **Reassignment.** Reassigning the card mid-run doesn't change the session's user.
  The next run on that card is owned per `run_owner_for` as before.
- **Per-user MCP credentials** don't change: they already read `session.user`.

**No user.** `session.user` can be nil only when `workflow_run.user` is nil. Those
sessions already fail the agent-credential preflight before they start, so no running
session has one today. The tools still guard it: the GitHub tools answer with an error
(§4.3), and the board, gate and asset tools keep their existing "Cannot determine …"
errors, now on `session_user`. `BoardMoveTask` and `BoardCreateGate`, which have no
such guard today, get one ("Cannot determine the acting user").

**Alternatives considered**

- *`Sessions::ActingUser`, a rule computed on each call* (the task's assignee, then the
  run's owner, then `session.user`). This was revision 1. Alex's review rejected it:
  it makes a second current user beside `session.user`, and it changes with
  reassignment while the session's credentials don't.
- *Leave the board tools on `resolve_actor` and use `session.user` only for the new
  tools.* That keeps two answers to the same question. Rejected by the review.

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

`GITHUB_APP_CLIENT_ID` and `GITHUB_APP_CLIENT_SECRET` already exist and enable user
connections. They no longer enable the installation check: that has its own setting,
`GITHUB_APP_VERIFY_INSTALLATION_OWNER` (off by default), so setting the credentials
for connections does not refuse installs made through the Setup URL.

### 4.2 Web routes (profile)

| Route | Action | Purpose |
|---|---|---|
| `GET /profile/connections` | `Web::Profile::ConnectionsController#index` | Inertia page `Profile/Connections` |
| `DELETE /profile/connections/:provider` | `Web::Profile::ConnectionsController#destroy` | disconnect |
| `PATCH /profile/connections/:provider/act_as_consents/:project_id` | `Web::Profile::ActAsConsentsController#update` | body `{ inOwnTasks?, inOthersTasks? }`, JSON booleans only (`422` otherwise) |
| `POST /oauth/github/authorize` | existing `Web::OauthController#authorize` | `owner_type=User&owner_id=<me>&return_to=/profile/connections` |

These are `resources` routes under `/profile`, like `sign_in_methods`. The controllers
turn the request into parameters and call the `UserConnections` service (the page's
data, disconnecting, updating a consent), then map its named errors to a status:
`UnknownProvider` and `ProjectNotFound` answer 404. The service resolves the project
with `Project.for_user_in_company(user, company)` and makes the first consent write
race-safe. The controller checks the body's shape: a switch that is not a JSON boolean
answers 422.

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
| `github_user_token` | none | `session_user` | `in_own_tasks` |
| `github_user_token_for` | `user_id` (integer, required; from `board_list_members` or a task's `assignee_id`) | that user | `in_own_tasks` if the user is `session_user`, otherwise `in_others_tasks` |

Shared logic goes in `InternalTools::Concerns::GithubUserTokenContext`. The steps
below run in order, and the first failure answers with an `error(...)`:

1. **Resolve the user.** Both tools first require `session_user`. If it is nil, the
   error is: "This session has no user, so there is no one to act as." Then
   `github_user_token` uses `session_user`, and `github_user_token_for` resolves
   `user_id` among the members of the session's company (an unknown id gives "No
   member with id <id> in this company.").
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
4. **One current user: `session.user`** (§2.4). This step needs none of 1–3 and can
   be merged first.
   - `InternalTools::Base`: add the private `session_user` (`session&.user`).
   - `BoardMoveTask`, `BoardAddComment`, `BoardAttachAsset`: delete `resolve_actor` and
     use `session_user`. Add the missing nil guard to `BoardMoveTask`.
   - `BoardCreateGate` (`creator:`), `PromoteAsset` (`promoter`),
     `TrackerAttachFiles` and `TrackerDownloadAttachments` (`user:`): use
     `session_user`. Add the nil guard to `BoardCreateGate`.
   - Rewrite the comment above `TaskService.run_owner_for` so it describes the tools'
     actor as `session.user`.
   - Repeat the §2.4 search. Any reader it finds that is not in the §2.4 tables gets
     a row in this document in the implementation pull request, and is switched to
     `session.user` if it computes the session's user another way.
   - Docs: in `docs/user-guide/index.md` and its mirrors
     `app/frontend/pages/Docs/data/pages/user-guide.md` and `starting-work.md`, extend
     the "A session runs on a person's credential" paragraph: the session also acts as
     that person, so the agent's board comments, attachments, moves and gates, and its
     tracker uploads, are recorded under their name.
   - `CHANGELOG.md`: an entry under `### Changed` with the **Tasks** area, saying that
     an agent's board comments, attachments and moves are now recorded under the
     session's user instead of the card's assignee.
5. **Tools.**
   - Add `InternalTools::GithubUserToken`, `InternalTools::GithubUserTokenFor` and
     the `GithubUserTokenContext` concern.
   - Add the `:github_identity` entry to `Tools::TagCatalog`.
6. **Profile UI.**
   - Add the connections and act-as-consents controllers, the `UserConnections` service and their
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

Steps 1–3 can be merged on their own, because nothing calls them yet. Step 4 is
independent of the others. Step 5 needs 1–4. Step 6 needs 1–2.

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
- **`session.user` (step 4):**
  - `test/services/internal_tools/board_write_tools_test.rb`: replace "uses
    workflow_run user as fallback author" with tests where the card's assignee is
    someone other than the session's user. The comment, the asset and the move's
    board activity name the session's user. A move of a card whose assignee can't
    own runs fires the next run owned by the session's user.
  - `board_create_gate_test.rb` and `promote_asset_test.rb`: the creator and the
    promoter are the session's user, and a session without a user gets the error.
  - `tracker_attachment_tools_test.rb`: the exporter and importer receive the
    session's user.
- **Tools** (`test/services/internal_tools/github_user_token_test.rb` and
  `github_user_token_for_test.rb`, in the shape of `get_config_item_test.rb`):
  - every error in §4.3, including a session without a user, and the consent matrix
    (own versus others, the named user being the session's user);
  - a card whose assignee is not the session's user: `github_user_token` returns the
    session's user, not the assignee;
  - several owners giving several tokens, and PAT repositories in `skipped`;
  - a refusal when `SecretRegistry.publish!` fails;
  - the issuance row is written, and the token appears in `SecretRegistry#values` and
    `SecretRedactor.secret_values_for`;
  - no token in any error.
- **Masking:** `secret_registry_test.rb` and `secret_redactor_test.rb` cover a session
  with issuances and no secret config items.
- **MCP:** no change. The existing `session_context_service_test.rb` tests already
  pin the per-user credential to `session.user`.
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
- **R3. Redirect URIs on the App.** The user flow redirects to `/oauth/callback`, which
  the App lists as a **Redirect URI** under "Identifying and authorizing users"; token
  expiration is on under **Optional Features → User-to-server token expiration → Opt-in**.
  The installation check is a separate opt-in (`GITHUB_APP_VERIFY_INSTALLATION_OWNER`,
  off by default): the client credentials alone enable only connecting accounts. With
  the check on, "Request user authorization (OAuth) during installation" is on, and
  `/company/integrations/github_setup` must be the **first** Redirect URI, because GitHub
  then makes the Setup URL unavailable and sends installs to the first one. Staging and
  aixle.com leave the check off, so installing through the Setup URL keeps working.
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
- **R7. Attribution moves for three board tools.** After step 4, an agent's comments,
  attachments and moves on a card whose assignee isn't the session's user are
  recorded under the session's user (§2.4, behaviour changes). A workflow or a report
  that reads "comments by the assignee" to find agent output would see them under
  another name. `board_get_comments` filters by `author_type` and tag, not by author,
  so the tools themselves are not affected. The changelog entry for step 4 states the
  change.
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
| D1 | The session's current user is `session.user`, everywhere. There is no `Sessions::ActingUser`. The board, gate, asset and tracker tools switch to it; per-user MCP credentials already read it. | Alex's design review, 2026-11-10 |
| D2 | `session.user` is set once at creation: the launching user for an interactive session, a copy of `workflow_run.user` for a step. `workflow_run.user` is chosen at run start by `run_owner_for` for a card, the starter for a manual run, and the run-as user for a trigger. | Alex's design review; `SessionService.create_and_start`, `SessionService#build_for_workflow_step` |
| D3 | The agent credential, billing and the GitHub tools all act as the same person, `session.user`. When a card's assignee can't own runs, that is the run's owner. | Alex's design review |
| D4 | `github_user_token_for` checks "in my tasks" when the named user is `session.user`. Any other user needs "in tasks that aren't mine". | Alex's design review |
| D5 | "In my tasks" means "in sessions whose user I am", in that project, whether or not the session has a card and whoever the card's assignee is. | Alex's design review (D4 and D5) |
| D6 | The connection is user-level, one GitHub account per Flow user across companies. Consent is per project. The profile page lists the projects of the current company. | Task §1 ("in the user's own settings"); the profile pages render in the current company |
| D7 | Disconnect revokes the grant at GitHub and deletes the user's GitHub consents. Reconnecting starts with both switches off. A reconnect from `needs_reconnect` (no disconnect) keeps them. | Accepted in Alex's design review |
| D8 | The tools are `user_attachable` with no auto-injection. They appear in the picker under "GitHub as a user". | Task §2: "whoever configures a workflow or a session decides which tool the agent gets" |
| D9 | Only repositories on a GitHub **App** connection are covered. PAT-connected repositories are skipped with a reason. | The scoped endpoint needs the App installed on the target |
| D10 | `user_id` is the only way to name a user. | Board tools expose member ids (`board_list_members`, `assignee_id`) |
| D11 | The existing `GITHUB_APP_CLIENT_ID` / `SECRET` gate the feature; the installation check has its own setting, `GITHUB_APP_VERIFY_INSTALLATION_OWNER`, off by default. | `config/settings.yml` `github.*` |
| D12 | The platform does not set the commit identity, sign-off or `gh` credentials for the session. It returns the identity, and the instructions apply it. | Task: "a workflow's instructions decide how to use it" |
| D14 | The tools read the session's user through one private helper, `InternalTools::Base#session_user`, so a search for it finds every reader. Readers outside the tools (container strategies, `SessionService`, resources) keep reading `session.user` directly. | Accepted in Alex's second review, 2026-11-11 |
| D15 | `workflow_run.user` readers that describe the run, not a session (`WorkflowService` retry and run activity, `Chat::StatusCard`, `PersonalTools::Base`), stay on it. | Accepted in Alex's second review, 2026-11-11 |

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
