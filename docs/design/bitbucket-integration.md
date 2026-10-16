# Bitbucket Cloud integration and provider-neutral pull-request tools — technical design

**Status:** Proposed.  
**Date:** 2026-10-15  
**Code baseline:** `affd849c`  
**Audience:** Backend, frontend and runtime engineers implementing the integration; whoever registers and operates the Forge app.  
**Related:** [azure-devops-integration.md](./azure-devops-integration.md) (installation model, PR tools, merge guard), [task-tracker-integrations.md](./task-tracker-integrations.md) (provider port, target resolution, write ledger, the YouTrack app pairing), [user-guide/gitlab.md](../user-guide/gitlab.md).

## 1. Decision and intended behavior

Add `bitbucket` as the fourth code host next to GitHub, GitLab and Azure DevOps. Three decisions were made on 2026-10-15:

1. **Bitbucket Cloud only.** Bitbucket Data Center is a different product to integrate: REST 1.0 with different paths and paging, no build-status webhook (CI gates could only poll), and project/repository HTTP access tokens that cannot merge pull requests. It needs its own adapter and is out of scope. Atlassian exempted Bitbucket Data Center from the Data Center end of life, so this may be requested later; nothing here should make it harder.
2. **Agents get pull-request tools, and GitLab gets them too.** Today a GitLab session can push a branch and nothing else: there are no merge-request tools and no `glab` in the image ([user-guide/gitlab.md](../user-guide/gitlab.md) says so). This design adds one provider-neutral `pull_request_*` tool set behind a port, implemented for GitLab and Bitbucket.
3. **The primary connection is an app, the way GitHub's is.** Customers install an **Aixle Flow Forge app** on their Bitbucket workspace. The app gives Aixle a bot identity and short-lived tokens, and delivers Bitbucket events. A token mode — a Bitbucket access token or API token pasted once — exists alongside it, as GitHub's PAT mode does: for self-hosted deployments that have not registered their own app, for development, and as a fallback.

Two more decisions followed on 2026-10-16:

4. **One "Atlassian" entry, two integrations.** Jira and Bitbucket cannot share a connection the way GitHub's code hosting and GitHub Projects do: they are separate tenants (a Jira site, a Bitbucket workspace) with separate auth (Jira's Atlassian OAuth app or a service account; Bitbucket's Forge app or tokens), a Forge app cannot span Jira and Bitbucket (cross-product apps exclude Bitbucket, and mixing their scopes fails `forge deploy`, ECO-329), and a scoped API token is created for one product. So the Connect menu offers one **Atlassian** item that opens a chooser — **Jira** (issues as trackers) or **Bitbucket** (repositories, pull requests, CI gates) — and each choice runs its own flow and creates its own integration.
5. **Issue keys link the two.** A run started from a tracker issue starts branch names with the issue key and prefixes pull-request titles with it (`pull_request_create` adds it when the agent did not). Jira's development panel then lists the branches, commits and pull requests by itself when the customer's Atlassian organization links Jira with Bitbucket — and the same holds for GitHub and GitLab with Jira's apps for them. No integration of ours carries that link.

| User outcome | GitLab today | GitLab after | Bitbucket |
|---|---|---|---|
| Connect a code host | Personal access token | Unchanged | Forge app (primary); access token or API token |
| Pick repositories and branches | Yes | Unchanged | Yes |
| Clone, fetch, push in a session | Credential helper | Unchanged | Credential helper |
| Open, inspect and update pull requests | — | `pull_request_*` tools | `pull_request_*` tools |
| Read and answer review comments | — | Yes | Yes |
| Approve, request changes | — | Yes | Yes |
| Merge | — | Yes, guarded by expected head commit | Yes, guarded by expected head commit |
| Wait for CI | `gitlab_pipeline_completed` | Unchanged | `bitbucket_pr_statuses_completed` |
| Attach a public repository | gitlab.com | Unchanged | bitbucket.org |

Out of scope: Data Center; Bitbucket issues (Jira already covers Atlassian tracking); workflow triggers on push or pull-request events (no code host has them today — Forge events make them cheap to add later, §11); Coder workspaces (GitHub and public repositories only today); moving GitHub or Azure DevOps onto the new port (§4.2).

## 2. Facts the design rests on

Checked against Atlassian documentation in October 2026. Each one changed the design; items still needing a live run are collected in §12.

- **App passwords are gone.** Creation stopped 2025-09-09; after brownouts they were removed on 2026-07-28 (REST answers 401, git 410). They are not supported. [Changelog](https://developer.atlassian.com/cloud/bitbucket/changelog/)
- **Connect is closed.** No new Connect apps since 2026-01-30, Forge-only updates since 2026-03-31, end of support 2027-01-31. A Bitbucket app today is a Forge app. [Announcement](https://community.developer.atlassian.com/t/bitbucket-cloud-announcing-connect-end-of-support-timeline-and-next-steps/98760)
- **Forge Remote pushes tokens; it never lends them.** The app system token (`x-forge-oauth-system`) arrives only with an invocation — a product event, a lifecycle event, a scheduled trigger or a UI call. "There is no endpoint for proactively refreshing the access token." Tokens are JWTs with at most 4 h of life; a scheduled trigger routed straight to a remote endpoint is guaranteed a token with at least 2 h left. The shortest schedule is five minutes. [Calling product APIs](https://developer.atlassian.com/platform/forge/remote/calling-product-apis/), [scheduled triggers](https://developer.atlassian.com/platform/forge/remote/scheduled-triggers/)
- **A token delivered with a UI call can be older than one we already hold.** Resolver-path tokens rotate about a minute before expiry; storing one blindly overwrote a fresher scheduled-trigger token and caused 401s (FRGE-2092). [Community report](https://community.developer.atlassian.com/t/forge-system-token-x-forge-oauth-system-refresh-behaviour-is-not-consistent/99941)
- **Every remote call carries a Forge Invocation Token** (`authorization: Bearer <FIT>`), signed by Atlassian, verifiable against a public JWKS, with `aud` = the app id and the installation and workspace in its claims. [Invocation contract](https://developer.atlassian.com/platform/forge/forge-remote-invocation-contract)
- **A Forge app cannot create repository webhooks** — webhook scopes are rejected at deploy, and Atlassian has no plans to change that. It does not need to: Forge product events cover the whole workspace, including `avi:bitbucket:{created,updated}:build-status`. [Events reference](https://developer.atlassian.com/platform/forge/events-reference/bitbucket/), [BCLOUD-24062 thread](https://community.developer.atlassian.com/t/forge-manifest-rejects-webhook-scopes-that-forge-lint-requires-for-bitbucket-webhook-endpoints/99878)
- **There is no install redirect.** Unlike a GitHub App's setup URL, Forge cannot pass state through an install or send the admin back to us. Binding an installation to an Aixle company has to start from inside Bitbucket (§5.5). [Distribution](https://developer.atlassian.com/platform/forge/distribute-your-apps/)
- **Access tokens have no "who am I".** `/2.0/user` refuses workspace, project and repository access tokens; they are verified by reading a repository. Workspace and project access tokens need the Premium plan. [BCLOUD-23528](https://jira.atlassian.com/browse/BCLOUD-23528), [access tokens](https://support.atlassian.com/bitbucket-cloud/docs/access-tokens/)
- **Git usernames differ by credential:** `x-token-auth` for access tokens and the Forge app token, `x-bitbucket-api-token-auth` for a scoped API token. Our credential vendor currently answers `oauth2` for every non-GitHub host. [Using API tokens](https://support.atlassian.com/bitbucket-cloud/docs/using-api-tokens/), [Forge git operations](https://developer.atlassian.com/platform/forge/remote/bitbucket-git-operations/)
- **Cross-workspace listing endpoints are gone** (410 since 2026-04-14). Repositories are listed per workspace. [EOL notice](https://community.developer.atlassian.com/t/bitbucket-cloud-announcing-end-of-life-for-cross-workspace-apis-timeline-next-steps-and-instructions-for-connect-apps/99972)
- **Merging takes no expected commit.** `POST …/pullrequests/{id}/merge` accepts `merge_strategy`, `close_source_branch` and `message` only, and may answer 202 with a task to poll (checked in the live OpenAPI spec, `swagger.v3.json`). The head-commit guard has to be ours.
- **There is no "pipeline finished" event.** CI is visible as commit statuses (`SUCCESSFUL | FAILED | INPROGRESS | STOPPED`) written by Pipelines and by external CI alike.
- **Rate limit:** 1,000 requests/hour per user (the app's bot user counts as one) on `/2.0/repositories/*`, scaled up to 10,000 for Standard/Premium workspaces with 100+ paid seats; Forge `asApp` calls qualify for the scaling. [API request limits](https://support.atlassian.com/bitbucket-cloud/docs/api-request-limits/)
- **No maintained Ruby client** (the newest, `tinybucket`, last released 2018) and **no usable CLI** (`acli` has no Bitbucket commands; the third-party `bkt` is not something to put in the agent image). The client is ours, on Faraday, like `AzureDevops::Client`.

## 3. Existing code and required changes

| Existing component | Observed behavior | Change |
|---|---|---|
| [Integration](../../app/models/integration.rb) | `CONNECTABLE_PROVIDERS` and the `provider` enum (:10, :12); Azure has an installation FK | Add `bitbucket`; add `bitbucket_installation_id`; Bitbucket accessors |
| [Repository](../../app/models/repository.rb) | `CODE_HOST_PROVIDERS = %w[github gitlab azure_devops]` (:16); `set_clone_url` per provider (:133); `PUBLIC_HOSTS` (:9) is the SSRF allowlist; `external_*` identity used by Azure only | Add the provider, clone URL, `bitbucket.org` public host, and identity by workspace/project/repository UUID (§6.4) |
| [RepositoryService](../../app/services/repository_service.rb) | Factory raising "Unsupported provider" | Add `Bitbucket::RepositoryService` |
| [IntegrationsController](../../app/controllers/web/company/projects/integrations_controller.rb) | `create`/`update`/`test_connection` switch on provider; **an unmatched provider in `update` falls through to `coder_service.update_settings` (:54)** | Explicit Bitbucket branches; installation-attach and pairing actions |
| [GitCredentials::Vendor](../../app/services/git_credentials/vendor.rb) | `PROVIDERS = %w[github gitlab]`; username `x-access-token` for GitHub, `oauth2` for anything else (:34) | Add Bitbucket; username by credential kind |
| [Repositories::CiWebhook](../../app/services/repositories/ci_webhook.rb) | Registers a per-repository hook for GitLab only | No change: Bitbucket uses Forge events, or the sweep in token mode (§8) |
| [Gate](../../app/models/gate.rb), [GateService](../../app/services/gate_service.rb), [Ci::GateProbe](../../app/services/ci/gate_probe.rb), [GateReconciler](../../app/services/gate_reconciler.rb) | Gate type → provider by prefix; metadata scopes cast to integers; `PASSING_CONCLUSIONS` lowercase; verdict key is `status` for GitLab, `conclusion` otherwise (:171) | New gate type keyed by repository UUID and pull request (§8) |
| [BoardCreateGate](../../app/services/internal_tools/board_create_gate.rb), [TaskStatisticsResource](../../app/resources/task_statistics_resource.rb) | Gate-type enum in the tool schema; TS union that already omits the two Azure gate types | Add the Bitbucket type; fix the Azure omission in the same change |
| [Tools::InjectionRules](../../app/services/tools/injection_rules.rb), [Tools::Context](../../app/services/tools/context.rb) | Closed rule vocabulary; synthetic capabilities for trackers and chat | Add `pull_request_repositories_attached` and a `pull_requests` capability (§4.6) |
| [ContextBuilders::Resources](../../app/services/context_builders/resources.rb) | Provider paragraphs: helper (:54), `gh` (:60), Azure tools (:65) | A paragraph for GitLab/Bitbucket PR tools |
| `config/templates/template.v1.json` | `requires.integrations` enum | Add `bitbucket` |
| [Gitlab::TokenService](../../app/services/gitlab/token_service.rb) | `gitlab` gem 6.1 client; only users, projects, branches, hooks and pipelines are used | Merge-request calls for the GitLab PR adapter |

## 4. Provider-neutral pull-request tools

### 4.1 Why a port, not CLIs or per-provider tools

- **CLIs** would need `glab` and a third-party Bitbucket CLI in the agent image, each with its own auth story, and give us no place to put the merge guard or idempotency. GitHub's `gh` works because the `gh-aixle` wrapper borrows the credential helper; nothing comparable exists for Bitbucket.
- **Per-provider tools** (the Azure route: 15 `azure_devops_*` tools) would mean a second and third copy of the same 10 operations, and a workflow written against one host would not run against another.
- **A port** gives one tool set, one ledger, one merge guard and one target-resolution rule, with only the HTTP mapping per provider. This is what the tracker design did for issues ([task-tracker-integrations.md](./task-tracker-integrations.md) §2), and the same argument holds: templates and workflows stay portable across hosts.

### 4.2 Scope of the port

Implemented for **GitLab and Bitbucket**. **GitHub keeps `gh`** — it works, and agents know it; a GitHub adapter (Octokit) can be added later if workflows need to be host-neutral, at which point `resources.rb` must tell agents which path to use. **Azure DevOps keeps its own tools**: they carry policies, votes and work-item links the port does not model, and moving them is churn with no user gain.

### 4.3 Port

`PullRequests::Provider.for(integration)`, with a `PullRequests::PROVIDERS` hash of class-name strings (`"gitlab"`, `"bitbucket"`), mirroring `Trackers::PROVIDERS`. Every method takes the Aixle `Repository` and checks that what it fetched belongs to that repository (Azure's `verify_pr_scope!`).

| Method | Returns |
|---|---|
| `list(repo, state:, source_branch:, cursor:, limit:)` | `Page<PullRequest>` |
| `get(repo, number)` | `PullRequest` |
| `changes(repo, number, cursor:, limit:)` | `Page<FileChange>` |
| `create(repo, source_branch:, target_branch:, title:, description:, draft:)` | `PullRequest` |
| `update(repo, number, title:, description:, target_branch:, draft:, state:)` | `PullRequest` (`state` open/closed — decline on Bitbucket, close on GitLab) |
| `list_comments(repo, number, cursor:, limit:)` | `Page<Comment>` |
| `add_comment(repo, number, body:, file_path:, line:, reply_to:)` | `Comment` |
| `review(repo, number, verdict:, body:)` | `Review` (`approve`, `unapprove`, `request_changes`) |
| `merge(repo, number, expected_head_sha:, strategy:, delete_source_branch:, message:)` | `MergeResult` |
| `checks(repo, number)` | `Checks` |
| `owns_reference?(repo, url_or_number)` | Boolean — for resolving a pasted PR URL |

### 4.4 Value objects

`Data.define` with the `Trackers::Value` JSON mixin; `Page(items, next_cursor)` reused as is.

- `PullRequest(number, url, title, description, state, draft, source_branch, target_branch, head_sha, author, reviewers, mergeable, created_at, updated_at)` — `state` normalized to `open | merged | closed`.
- `Comment(id, parent_id, author, body, file_path, line, resolved, created_at)` — threads kept, as Azure's service argues: a reply has to land in its thread.
- `FileChange(path, old_path, status, additions, deletions)`.
- `Review(reviewer, verdict, submitted_at)`.
- `Checks(state, items)` — `state` `pending | passed | failed | none`, items `{name, status, url}`.
- `MergeResult(merged, already_merged, pending, pull_request)`.

### 4.5 Tools

All `tags :pull_requests` (hidden, like `:azure_devops`), `inject_when :pull_request_repositories_attached`, `user_attachable false`, `requires_integration :pull_requests`. None declares `repository_binding :legacy_github`.

| Tool | Parameters (besides `repository_id`) | Ledger |
|---|---|---|
| `pull_request_list` | `state`, `source_branch`, `limit`, `cursor` | — |
| `pull_request_get` | `pull_request` (number or URL) | — |
| `pull_request_changes` | `pull_request`, `limit`, `cursor` | — |
| `pull_request_checks` | `pull_request` | — |
| `pull_request_create` | `source_branch`*, `target_branch`, `title`*, `description`, `draft` (default true), `operation_key` | yes |
| `pull_request_update` | `pull_request`*, `title`, `description`, `target_branch`, `draft`, `state` | — (idempotent) |
| `pull_request_list_comments` | `pull_request`*, `limit`, `cursor` | — |
| `pull_request_add_comment` | `pull_request`*, `body`*, `file_path`, `line`, `reply_to`, `operation_key` | yes |
| `pull_request_review` | `pull_request`*, `verdict`*, `body`, `operation_key` | yes |
| `pull_request_merge` | `pull_request`*, `expected_head_sha`*, `strategy`, `delete_source_branch`, `message`, `operation_key` | yes |

`target_branch` defaults to the repository's `source_branch` in Aixle — the branch sessions check out, chosen when the repository was attached — rather than the host's default branch. `pull_request_create` first looks for an open pull request from the same source to the same target and returns it (`existing: true`) rather than creating a second one; both hosts refuse or confuse duplicates, and an agent retrying after a timeout should get the one it made.

### 4.6 Availability and injection

- `PullRequests::CAPABILITY = "pull_requests"`, added to `Tools::Context#connected_providers` when the project has an active GitLab or Bitbucket integration — the way `Trackers::CAPABILITY` is (`context.rb:54`). `requires_integration` takes one provider, which is why a capability is needed.
- `pull_request_repositories_attached: ->(ctx) { ctx.repository_providers.intersect?(PullRequests::PROVIDERS.keys) }`. A session with only GitHub or Azure repositories does not see these tools.

### 4.7 Target resolution

`repository_id` is optional and resolves deterministically, never by row order (`Trackers::TargetResolver` rule):

1. Explicit `repository_id` — must be in `session.repositories` and PR-capable; the integration comes from the repository, then the project/company ownership check (`azure_devops_context.rb:29-42, 86-91`).
2. A `pull_request` given as a URL — the unique attached repository that `owns_reference?` it.
3. The only PR-capable repository attached to the session.
4. Otherwise `repository_required`, listing the candidates.

### 4.8 Idempotency and attribution

One neutral ledger, `pull_request_operations` (§6.5), unique on `(integration_id, operation_key)`, with `request_digest` and the states `pending | succeeded | failed | unknown`. `operation_key` is optional; when absent it is derived from the session, operation and payload digest, as `tracker_context.rb:71-73` does. A replay with the same key and digest returns the recorded result; the same key with a different payload is a `conflict`. The row carries `terminal_session_id`, `workflow_run_id`, `workflow_id` and the target PR, so later PR events (§11) can be attributed to the run that caused them.

### 4.9 Merge guard

Taken from the Azure implementation (`pull_request_service.rb:226-300`), where Azure was shown to ignore its own expected-commit field:

1. `expected_head_sha` is required.
2. Read the pull request. Already merged → `already_merged: true`. Closed → `conflict`.
3. Compare the head commit locally. A mismatch is a `conflict` with `{current_head_sha, expected_head_sha}` — the agent has to look at what changed.
4. Send the merge. GitLab also receives `sha:` and enforces it server-side. **Bitbucket has no such parameter**, so a push landing between our read and the merge call is merged unseen; the window is one request long and the design accepts it, but the tool result reports the merged head so the agent can notice.
5. Never bypass approvals, branch restrictions or merge checks.
6. Bitbucket may answer 202: poll `merge/task-status/{id}` up to a configured number of times, then report `pending: true` rather than wait.
7. Merging is a per-connection capability, on by default — the Azure decision of 2026-09-13 — and can be turned off per integration.

### 4.10 Errors

`PullRequests::Error(code, message, details)` with the Azure codes — `not_found_or_inaccessible`, `not_authorized`, `permission_denied`, `validation_failed`, `conflict`, `rate_limited` (with `retry_after`), `outcome_unknown`, `integration_unavailable` — plus `unsupported` for an operation a provider cannot do (§4.11). Tool results are `error(e.to_h.to_json)`, as in the Azure and tracker tools.

### 4.11 Provider mapping

| Operation | GitLab (gem `gitlab` 6.1) | Bitbucket Cloud (REST 2.0) |
|---|---|---|
| list / get | `merge_requests`, `merge_request` (iid) | `GET …/pullrequests?state=`, `…/pullrequests/{id}` |
| changes | `merge_request_diffs` (paths only) | `GET …/pullrequests/{id}/diffstat` |
| create | `create_merge_request`; draft through the `Draft:` title prefix | `POST …/pullrequests` with `draft` |
| update / close | `update_merge_request` (`state_event: close`) | `PUT …/pullrequests/{id}`; close = `POST …/decline` |
| comments | notes and `discussions`; inline needs `position` built from the MR's `diff_refs` | `GET/POST …/comments` with `inline {path, to}` and `parent {id}` |
| review | `approve_merge_request` / `unapprove_merge_request`; `request_changes` → `unsupported` until the instance's request-changes review state is verified | `POST/DELETE …/approve`, `POST …/request-changes` |
| merge | `accept_merge_request` with `sha:`, `squash`, `should_remove_source_branch` | `POST …/merge` (`merge_strategy`, `close_source_branch`, `message`), 202 → task-status |
| checks | MR `head_pipeline` plus `repository/commits/:sha/statuses` | `GET …/pullrequests/{id}/statuses`, filtered to the head commit |

On GitLab the token's owner is the author of everything the tools do. The user guide should recommend a project or group access token (a bot user) over an employee's personal token; both pass the existing `/user` verification.

### 4.12 What agents are told

`resources.rb` gains a paragraph for sessions holding GitLab or Bitbucket repositories: pull requests go through the `pull_request_*` tools; there is no `glab` or Bitbucket CLI; use `pull_request_checks` or a gate to wait for CI; merge only with the head commit you reviewed. When the run came from a tracker issue and the session holds any code-host repository, the agent is also told to start branch names with the issue key and put it at the start of pull-request titles and commit messages (decision 5, §1); `pull_request_create` prefixes the title itself when the key is missing.

## 5. Bitbucket connection model

### 5.1 Two modes

| | App mode (primary) | Token mode |
|---|---|---|
| Credential | Forge app system token, pushed to us, ≤4 h | Access token (workspace/project/repository) or scoped API token, pasted once |
| Identity on Bitbucket | The app's bot user | The access token's bot, or the API token's user |
| Scope | Every repository of the workspace the app user can reach | What the token reaches |
| CI events | Forge `build-status` events | None — the reconciler sweep resolves gates |
| Available when | `BITBUCKET_FORGE_APP_ID`, `BITBUCKET_FORGE_ENVIRONMENT_ID` and `BITBUCKET_FORGE_INSTALL_URL` are set — no enable flag | Always, as GitHub PAT mode |

Both modes share the client, repository service, credential vending, PR adapter and gate probe. Only how a token is obtained differs (`Bitbucket::CredentialProvider`).

### 5.2 The Forge app

Lives at `bitbucket-app/` next to `youtrack-app/`: a manifest and one small Custom UI page. **It has no Forge functions.** Every module routes to a remote endpoint on the Aixle deployment, so nothing is metered by Forge pricing (remote invocations are free), and all logic stays in Rails.

Manifest sketch — exact module keys and fields are confirmed in the spike (§12):

```yaml
app:
  id: ${FORGE_APP_ID}
permissions:
  scopes:
    - read:app-system-token
    - read:workspace:bitbucket
    - read:project:bitbucket
    - read:repository:bitbucket
    - write:repository:bitbucket
    - read:pullrequest:bitbucket
    - write:pullrequest:bitbucket
    - read:pipeline:bitbucket
  external:
    fetch:
      client:
        - ${AIXLE_BASE_URL}          # lets the page open Aixle without the external-link prompt
remotes:
  - key: aixle
    baseUrl: ${AIXLE_BASE_URL}
    operations: [storage, other]
    storage:
      inScopeEUD: true
endpoint:
  - key: lifecycle
    remote: aixle
    route: { path: /webhooks/bitbucket/forge/lifecycle }
    auth: { appSystemToken: { enabled: true } }
  - key: events      # route /webhooks/bitbucket/forge/events, same auth
  - key: heartbeat   # route /webhooks/bitbucket/forge/heartbeat
  - key: ui          # route /webhooks/bitbucket/forge/ui
  - key: uninstall   # route /webhooks/bitbucket/forge/uninstall
modules:
  trigger:
    - key: lifecycle
      endpoint: lifecycle
      events: [avi:forge:installed:app, avi:forge:upgraded:app]
    - key: repository-events
      endpoint: events
      events:
        - avi:bitbucket:created:build-status
        - avi:bitbucket:updated:build-status
        - avi:bitbucket:updated:repository
        - avi:bitbucket:deleted:repository
  scheduledTrigger:
    - key: token-heartbeat
      endpoint: heartbeat
      interval: fiveMinute
  preUninstall:
    - key: uninstall
      endpoint: uninstall
  bitbucket:workspaceSettingsMenuPage:
    - key: connect
      title: Aixle Flow
      resource: connect-page
      resolver: { endpoint: ui }
resources:
  - key: connect-page
    path: static/connect/build
```

`read:pullrequest:bitbucket` is requested now although no PR event is subscribed: adding a scope later is a major version that every workspace admin has to approve again, while adding a trigger under an existing scope is not.

### 5.3 Verifying invocations

Every request to `/webhooks/bitbucket/forge/*` carries a FIT. `Bitbucket::Forge::InvocationToken` verifies it before anything else runs:

- signature against the Forge JWKS (`https://forge.cdn.prod.atlassian-dev.net/.well-known/jwks.json`), keys cached with `kid` rotation, algorithm pinned rather than taken from the header;
- `iss = forge/invocation-token`, `aud` = `BITBUCKET_FORGE_APP_ID`, `exp` in the future with a small skew;
- `app.environment.id` = `BITBUCKET_FORGE_ENVIRONMENT_ID`, so a development install can never reach production data even through a misrouted URL;
- the installation (`app.installationId`) and workspace (`app.installation.contexts[].workspaceId`) are taken from the verified token, never from the body.

With no app id configured the endpoints answer 401, as the GitHub webhook does without a secret. The controller writes the delivered system token (§5.4), enqueues any work and acknowledges within Forge's 5-second budget. A 3xx counts as a failure to Forge, so nothing on this path redirects. The `x-forge-oauth-system` and `authorization` headers are scrubbed from Sentry request data.

### 5.4 Holding a valid token

The backend can never ask for a token, so the design makes sure one keeps arriving and is never replaced by a worse one.

- **Source.** The five-minute `scheduledTrigger` routed straight to the `heartbeat` endpoint is the backbone: each tick brings a token guaranteed ≥2 h of life. Lifecycle, product-event and UI invocations also bring tokens and are stored by the same rule.
- **Write rule.** Compare-and-set on expiry, so an older resolver token cannot overwrite a fresher one (FRGE-2092):
  `UPDATE bitbucket_installations SET encrypted_access_token = $1, token_expires_at = $2, last_invocation_at = now() WHERE id = $3 AND (token_expires_at IS NULL OR token_expires_at < $2)`.
  `token_expires_at` is read from the token's `exp` claim; the token is otherwise opaque to us.
- **Read rule.** `Bitbucket::CredentialProvider` hands a token out only while it has at least `BITBUCKET_TOKEN_MIN_REMAINING` (default 5 minutes) left. Otherwise it raises `CredentialUnavailable` naming the installation and how long it has been silent — there is nothing to fetch, so the right behaviour is a fast, legible failure.
- **401 with an unexpired token.** Re-read the row once (a newer token may have landed between the read and the call) and retry once; a second 401 marks the installation `error / access_revoked` and its project integrations `error`. One retry, never a loop — the `AppTokenService` rule.

| Failure | Effect | Recovery |
|---|---|---|
| Our endpoint down or slower than 5 s | Ticks fail (Forge retries 4×, 60 s apart); stored tokens keep working until they expire, ≥2 h after the last good tick | First tick after recovery, ≤5 min |
| App redeployed | Schedules reset; first tick ~5 min after deploy | Covered by the 2 h floor |
| Major version waiting for admin consent | The installation stays on the old version, which keeps ticking | None needed |
| Ticks stop for an installation | `last_invocation_at` ages; health becomes `silent` after 15 minutes and the UI shows it | Investigate; reinstall if Forge lost the installation |
| App uninstalled | `preUninstall` marks it (§5.6); if that call is lost, the next 401 does | — |

A sweep (the existing Temporal pattern of sweeping expiring rows, `app/temporal/schedules.yml`) reports installations whose token expires within 30 minutes; that is the alert worth having.

### 5.5 Binding an installation to a company

There is no install redirect, so the binding starts inside Bitbucket and finishes inside Aixle. It follows the YouTrack pairing (`YoutrackPairing`, `docs/design/task-tracker-integrations.md` §12 phase 5): a short-lived, single-use secret, stored only as a digest, joining an identity proven on each side.

1. In Aixle, a user opens a project's Integrations page → **Connect Bitbucket** and types the workspace. If the company already has an installation bound for it, the project is connected (step 8). Otherwise Aixle shows the install link (`BITBUCKET_FORGE_INSTALL_URL`) and the next step to take in Bitbucket, and remembers the project in the user's session. The dialog never lists the company's bound workspaces: the Azure dialog stopped listing bound organizations because it told every project member which organizations the company works with (`integrations_controller.rb:366-372`), and the same holds here.
2. A workspace admin installs the app (Bitbucket allows only admins, and only on team workspaces). `avi:forge:installed:app` reaches the `lifecycle` endpoint; Aixle records an **unbound** installation with its token.
3. The admin opens **Workspace settings → Aixle Flow → Connect**. The page calls `invokeRemote`; the FIT names the installation, the workspace and the admin's `accountId`.
4. The backend checks with the app token that this account administers the workspace (`GET /2.0/workspaces/{uuid}/permissions` filtered by `user.account_id`). An installation proves only that the *app* can reach the workspace, never who in Aixle should own it — the warning in `azure_devops_installation.rb:6-11` applies unchanged.
5. The backend creates a `bitbucket_pairings` row bound to the installation, workspace and account: a random secret stored as SHA-256, 10-minute TTL, single use. It returns `<AIXLE_BASE_URL>/integrations/bitbucket/connect#pairing=<id>.<secret>` — the secret in the fragment so no server log sees it.
6. The page opens that URL (`router.open`). Aixle asks the user to sign in if needed and shows a consent screen: the workspace name and slug, who started the connect, and the project to connect — preselected from step 1, limited to projects where the user may manage integrations.
7. On confirm, in one transaction with the installation row locked: an unbound installation takes the user's company; an installation bound to **another** company is refused, and its admin has to disconnect it there first. Aixle then lists one repository with the app token, and only on success creates or reuses the project's `Integration` (`provider: bitbucket`, `auth_mode: app`). A row that failed verification never claims anything — the rule from `integration.rb:270-271`.
8. Further projects in the same company connect by naming the workspace, which the server resolves against the company's own bound installations, with no Bitbucket round trip. As with Azure, once the binding exists it is the proof.

After binding, the Bitbucket settings page shows which Aixle company and project the workspace is connected to, by whom, with a **Disconnect** button (a UI invocation that unbinds the installation and puts its integrations into `error`). That is the detection and the remedy for the residual risk of this flow: an admin talked into sending their pairing link to someone else would connect their workspace to a stranger's company. The link is opened by the admin's own click, lives ten minutes and works once; the settings page then makes any wrong binding visible to the people who own the workspace.

One installation belongs to one company. GitHub's multi-company sharing needed a user-authorization proof Bitbucket offers no equivalent of.

### 5.6 Lifecycle

| Event | Effect |
|---|---|
| `avi:forge:installed:app` | Upsert unbound installation by `installationId`; store token; keep `installerAccountId` |
| `avi:forge:upgraded:app` | Store token; record app version |
| Heartbeat tick | Store token by the write rule; update `last_invocation_at` |
| `preUninstall` | Status `uninstalled`; wipe the token; project integrations → `error` ("The Aixle Flow app was removed from this workspace"); later clones fail fast with that message |
| Reinstall | A new `installationId` for the same workspace UUID arrives unbound. Rebinding goes through the pairing again; on confirm, the company's existing Bitbucket integrations move to the new installation, so their repositories survive |
| Disconnect in Bitbucket | Installation unbound; integrations `error` |
| Remove the integration in Aixle | Destroys the project integration only; the installation stays bound for the company's other projects |
| `avi:bitbucket:updated:repository` | Refresh the repository's `full_name` and `clone_url` from its UUID (renames, transfers) |
| `avi:bitbucket:deleted:repository` | Mark matching repository rows unavailable; may arrive up to 30 days late |

The install event can arrive before Bitbucket has applied the app's permissions; a 401/403 during the first verification is retried rather than treated as revoked.

### 5.7 Token mode

- **Form:** workspace slug and token. The kind is detected rather than asked. `GET /2.0/user` succeeds → a scoped API token (identity = the user's UUID). Otherwise `GET /2.0/repositories/{workspace}?pagelen=1` succeeds → an access token (identity = the workspace UUID; the bot has none we can read). Neither → `not_authorized`. Nothing is saved before one check passes — the GitLab rule.
- **Git username:** `x-token-auth` for an access token, `x-bitbucket-api-token-auth` for an API token. REST uses `Authorization: Bearer` for both.
- **Scopes to document:** repository read and write, pull request read and write, pipeline read; for an API token also `read:user` and `read:workspace`. An API token's `write:repository` does not imply read; both are needed.
- **Reconnecting** with a token of the same identity replaces the credential in place, as GitLab does, so repositories stay attached.
- **No webhooks.** CI gates resolve through the reconciler sweep only, the way GitHub PAT connections already do. This keeps a single event ingress (Forge) and avoids another hook-id column; per-repository webhooks with `X-Hub-Signature` can be added later if the sweep's latency is a problem.
- **API tokens expire** within a year. `test_connection` reports the 401 as a token to replace, never as an outage.

### 5.8 Environments and self-hosting

- **Our deployments.** One app registration with Forge environments: `production` → `https://flow.aixle.com`, `staging` → the staging host, `development` → each developer's tunnel. `baseUrl` comes from a manifest environment variable at `forge deploy` (`${AIXLE_BASE_URL}`; Forge CLI 13.3 broke this briefly in August 2026, since mitigated). Each environment has its own installations, so staging only ever receives tokens for workspaces installed on staging. That is unlike Azure, where one app registration could mint tokens for every tenant and staging was left without the integration for that reason.
- **Self-hosting operators** either use token mode (nothing to register) or run their own app: `forge register`, `forge deploy -e production` with their base URL, install it with the sharing link, and set the three `BITBUCKET_FORGE_*` variables. Their deployment must be reachable from the internet. Forge's customer-managed remotes (GA 2026-10-12) might later let operators use our app with their own URL; it is unverified for Bitbucket and would cost the app any "Runs on Atlassian" eligibility.
- **Configuration:** `BITBUCKET_FORGE_APP_ID`, `BITBUCKET_FORGE_ENVIRONMENT_ID`, `BITBUCKET_FORGE_INSTALL_URL`, optional `BITBUCKET_TOKEN_MIN_REMAINING` and `BITBUCKET_FORGE_JWKS_URL`. Documented in `docs/reference/configuration.md` and copied to the portal's `config-schema.md`.

### 5.9 Distribution and cost

- Installed through a **sharing link** from the developer console; no installation cap is documented (checked in the spike). A free Marketplace listing can come later; an app submitted to Marketplace or licensed can no longer use sharing links, so that switch is deliberate.
- No Forge functions means no metered Forge usage. The first month's usage page confirms it.
- With remote egress the app is not eligible for "Runs on Atlassian" or data residency. The manifest declares remote storage of end-user data (`inScopeEUD: true`), which is true: PR titles, comments and repository metadata pass through and land in session logs.

## 6. Data model

### 6.1 `bitbucket_installations`

Modelled on `azure_devops_installations` (db/schema.rb:149-172), with one difference: the cache is written by pushes, never by a mint.

| Column | Notes |
|---|---|
| `forge_installation_id` | Unique. Changes on reinstall |
| `workspace_uuid` | Immutable after create. Survives reinstall and rename |
| `workspace_slug`, `workspace_name` | Display only; refreshed from events |
| `company_id` | Null while unbound |
| `bound_by_id`, `bound_at` | Who confirmed the pairing |
| `installer_account_id` | From the install event |
| `status` | `unbound | active | error | uninstalled` |
| `error_code` | `access_revoked`, `uninstalled`, … |
| `encrypted_access_token`, `token_expires_at` (indexed) | `Encryptable` under `integrations_key`; an unreadable entry is a cache miss, as in the Azure model |
| `last_invocation_at`, `app_version` | Health and support |

### 6.2 `bitbucket_pairings`

As `youtrack_pairings`: `installation_id`, `account_id`, `workspace_uuid`, `secret_digest`, `expires_at`, `consumed_at`, `consumed_by_id`, `project_id`. Unknown pairing and wrong secret both answer 404.

### 6.3 `integrations`

- `provider` and `CONNECTABLE_PROVIDERS` gain `bitbucket`.
- `bitbucket_installation_id` FK, `restrict_with_error`, required in app mode and absent in token mode; validated to belong to the same company (`azure_devops_connection_is_scoped` is the precedent).
- `settings`: `auth_mode` (`app | token`), `workspace_uuid`, `workspace_slug`, `token_kind` (`access_token | api_token`) and `account_uuid` in token mode, `enabled_capabilities` (merge). `credentials_data` holds the token in token mode only.
- A Bitbucket integration is always project-scoped.

### 6.4 `repositories`

- `full_name` = `workspace/repo_slug`. Both parts fit `FULL_NAME_FORMAT` (workspace IDs are lowercase letters, digits, `-` and `_`; slugs `[A-Za-z0-9._-]`), so no prefix is needed — unlike Azure.
- Identity: `external_organization_id` = workspace UUID, `external_project_id` = Bitbucket project UUID, `external_id` = repository UUID. The existing unique index `idx_repositories_external_identity` covers it. All three are set from verified API responses, and a validation requires them for Bitbucket rows as `azure_identity_is_complete` does for Azure. Every repository in Bitbucket Cloud belongs to a project, so `external_project_id` is never null; a null would defeat the unique index.
- `clone_url` = `https://bitbucket.org/<full_name>.git`. Events, gates and tools route on the UUIDs; `full_name` and `clone_url` are refreshed when the repository is renamed (§5.6), and a clone that answers 404 re-resolves the row by UUID once.
- No new columns: `webhook_secret` and `gitlab_hook_id` stay unused for Bitbucket.
- `PUBLIC_HOSTS` gains `bitbucket.org`, with `PublicRepositoryService` learning to check visibility anonymously (60 requests/hour per IP — the same constraint GitHub has) and to trim Bitbucket deep links (`/src/…`).

### 6.5 `pull_request_operations`

`integration_id`, `repository_id`, `operation_key` (unique with `integration_id`), `operation`, `request_digest`, `state`, `result` (jsonb), `pull_request_number`, `terminal_session_id`, `workflow_run_id`, `workflow_id`, `user_id`, timestamps. Shared by GitLab and Bitbucket.

### 6.6 `gates`

New gate type `bitbucket_pr_statuses_completed` (§8). Metadata: `repository_id`, `external_repository_id` (UUID), `pull_request_id`, optional `expected_commit`. Scopes on these keys compare strings: Bitbucket identifiers are UUIDs, and the existing scopes cast to `int`/`bigint`.

## 7. Git clone, fetch and push

The existing helper path (`GitCredentials::SessionGitSetup`) is reused unchanged: blobless clone with an `http.extraheader` read from a deleted 0600 file, then `git-credential-aixle` asking the platform on every `get`.

- `GitCredentials::Vendor::PROVIDERS` gains `bitbucket`; `clone_url` gains `https://bitbucket.org/<full_name>.git`.
- `Credential.username` comes from the credential kind: `x-token-auth` (app token, access token) or `x-bitbucket-api-token-auth` (API token). The current default of `oauth2` would fail on Bitbucket.
- `token_for` delegates to `Bitbucket::CredentialProvider`. In app mode a stale installation produces a clear clone failure through the existing `failed_repos` bookkeeping, naming the app and how long it has been silent.
- Pushes go out as the app's bot (app mode) or the token's identity. Commit authorship stays whatever the agent's git config says. Branch restrictions that do not allow the bot will refuse the push; the user guide says how to allow it.

## 8. CI gates

**Type:** `bitbucket_pr_statuses_completed` — "every CI status on the pull request's head commit has finished". It is keyed on the pull request rather than a pipeline because there is no pipeline-finished event and the build-status payload carries no pipeline UUID; commit statuses also cover CI outside Bitbucket Pipelines (Jenkins, CircleCI), which a pipeline key would miss.

**Probe** (`Bitbucket::CheckStatusService`, the reconciler's adapter):

1. Read the pull request. If `expected_commit` is set and the head has moved, the gate stays pending — a verdict about other code is not evidence (`GateService#mismatched_commit?`).
2. Read `…/pullrequests/{id}/statuses`, all pages, and keep the head commit's statuses.
3. None yet → in progress ("no CI status reported yet"); the gate's TTL ends a wait for CI that never starts. Any `INPROGRESS` → in progress. Otherwise completed: all `SUCCESSFUL` → `successful`; any `FAILED` or `STOPPED` → `failed`.

**Cue:** in app mode, `avi:bitbucket:{created,updated}:build-status` enqueues `ResolveBitbucketBuildStatusJob(repository_uuid, commit)`. The job finds pending gates for that repository UUID whose expected commit matches (or that have none) and calls `GateReconciler.reconcile`. The event is a cue to ask, never the verdict — the GitHub check-suite rule, because the first status to finish may be a lint while tests still run. In token mode there is no cue and the sweep resolves the gate.

**Model changes:** `CI_GATE_TYPES` and the enum; `provider` and `reference_type`; `PASSING_CONCLUSIONS` gains `successful`, Bitbucket's own vocabulary as Azure's `succeeded` is; the reconciler's verdict key; `BoardCreateGate` schema; the TS union in `TaskStatisticsResource`; a `bitbucket.org/<repo>/pull-requests/<n>` case in `gates.ts`.

## 9. Errors, limits and data handling

- **Workspace-wide credential in the container.** A GitHub session receives an installation token narrowed to one repository. A Bitbucket app token reaches every repository of the workspace that the app user can reach, and the credential helper hands it to the session for its remaining life (≤4 h). This is the same exposure a GitLab PAT has today (documented in `docs/user-guide/integrations.md`), not a new class, but it has to be stated in the Bitbucket user guide and in the security notes. Customers who need per-repository isolation use token mode with repository access tokens. The spike checks whether a workspace admin can restrict the app's repository access.
- **Event trust.** An event payload is used for IDs and as a cue; state is re-read through the API before anything acts on it (the tracker rule).
- **Rate limits.** One budget per installation (the bot user). The reconciler's probes (two calls per gate per probe), PR tools and repository listing (100 per page) share it. `429` → `rate_limited` with `retry_after`; the reconciler backs off rather than marking gates stale.
- **Transport failures** are never credential failures: an unreachable Bitbucket leaves the integration's status unchanged (`app_token_service.rb:103-105`).
- **Secrets** never reach logs, the browser or Sentry: `IntegrationResource` serializes explicit Bitbucket fields, never raw `settings` or credentials.

## 10. UI and documentation

- **Integrations page:** an **Atlassian** item in the Connect menu replaces the separate Jira item and opens a chooser between Jira and Bitbucket (decision 4, §1); each card says whether the project already has that connection, and a user can run both flows in one sitting. Integration rows keep their own provider labels. The Bitbucket modal, modelled on `GithubConnectModal`, has two paths: **Install the app** (recommended, shown when app mode is configured: type the workspace; a workspace the company already bound connects at once, any other gets the install link and the Bitbucket-side steps) and **Use a token** (workspace + token). Test connection and Replace token for token mode, as GitLab has.
- **`/integrations/bitbucket/connect`:** the consent page of §5.5.
- **Elsewhere:** Bitbucket logo in `IntegrationLogo`; labels in `IntegrationsContent` and `AddRepositoryModal`; copy in `RepositoriesContent` and the public-repository hint; integration health ("app silent for 20 min") on the integration row.
- **Documentation:**
  - a new `docs/user-guide/bitbucket.md` plus its five portal edits (page copy, `pages/index.ts`, `navStructure.ts`, `searchIndex.ts`, `DocsController::PAGES`);
  - in `docs/user-guide/gitlab.md`, replace "there are no GitLab tools for merge requests" with the new tools and the access-token recommendation;
  - rows in `integrations.md`;
  - `BITBUCKET_*` variables in `configuration.md`;
  - gate types in `references/aixle-system-reference.md`;
  - a new `docs/operations/bitbucket-app.md` (register, deploy per environment, install link, rotation, the self-hosting path);
  - an entry in `docs/index.md`;
  - a CHANGELOG entry under **Integrations**;
  - remove the stale "Bitbucket OAuth" line in `CONTRIBUTORS-INTERNAL.md`.

## 11. Implementation sequence

| Phase | Content | Depends on | Rough size, code + tests |
|---|---|---|---|
| 0. Spike | Forge app on a test workspace with a tunnel to a stub remote; answer §12 | — | 1–2 days, throwaway |
| 1. PR port + GitLab | Port, value objects, `pull_request_operations`, 10 tools, injection rule and capability, GitLab adapter, agent context paragraph, GitLab guide update | — | ~1.5–2k lines |
| 2. Bitbucket core, token mode | Faraday client, integration service, repositories and branches, credential vending, Bitbucket PR adapter, gate type and probe (sweep only), public bitbucket.org, token UI, user guide | 1 | ~2.5k lines |
| 3. Forge app | `bitbucket-app/`, FIT verifier, the five endpoints, installations and pairings, token cache, binding and consent UI, lifecycle, build-status cue, operations doc | 0, 2 | ~2.5–3k lines |
| 4. Later | Marketplace listing; push/PR workflow triggers from Forge events with run attribution through the ledger; GitHub adapter for the port; Data Center | 3 | — |

Phase 1 ships on its own and is useful to GitLab users the day it lands. Phase 2 makes every Bitbucket adapter testable and usable without the app. Phase 3 is the customer-facing launch: the app becomes the default path in the UI.

For scale: GitLab's integration is ~480 lines of code and ~1.1k of tests today; Azure DevOps landed at 13.4k lines in one PR.

## 12. Spike: what must be confirmed live

Phase 0 ends with an answer to each item, recorded in this document. A "no" on any of the first four changes the design.

1. A `fiveMinute` `scheduledTrigger` routed to a remote endpoint delivers a system token on every tick; its observed `exp`; how resolver tokens compare.
2. `git push` with the system token works, and works on a branch with restrictions once the app is allowed.
3. With the system token: create, comment, approve, request changes and merge a pull request. Who the author shows as. Whether the bot's approval counts toward required approvals. Whether a bot may approve a pull request it opened.
4. Bitbucket Pipelines produces `build-status` events, and their payload has the repository UUID and commit hash.
5. `GET /2.0/workspaces/{uuid}/permissions` with the app token tells a workspace admin from a member.
6. `preUninstall` fires on Bitbucket and carries a token or at least the installation.
7. The sharing link installs on a second, unrelated workspace.
8. Whether the app reaches every repository, including private ones, and whether an admin can restrict it to some.
9. Whether the workspace settings page is visible to admins only.
10. A workspace rename: what happens to `installContext`, events and git URLs.
11. Rate-limit headers seen for app calls.

## 13. Acceptance and validation

Contract tests pin an adapter to payloads we wrote. Four Azure defects passed a green suite that way and only live traffic disagreed, so each phase ends with a live run, not just CI.

**Live scenarios:**
- **App mode:** install → pair → attach a repository → a session clones it → the agent pushes a branch → `pull_request_create` → Pipelines runs → `bitbucket_pr_statuses_completed` resolves from the event within a minute → `pull_request_merge` with the reviewed head → uninstall → the integration shows the removal and the next clone fails with that message.
- **Token mode:** the same without events; the gate resolves on the sweep.
- **GitLab:** create, comment inline, approve and merge on gitlab.com; a moved head is refused locally and by `sha:`.

**Tests**, under [docs/testing.md](../testing.md):
- `Bitbucket::Client` and the GitLab adapter get WebMock contract tests with realistic payloads — taken from the OpenAPI spec and from the spike's recorded responses. The `gitlab` gem is never stubbed (`Testing/NoVendorStubbing`).
- One canonical `FakeBitbucket` at the app-owned service seam, and one `FakePullRequests` provider for tool tests, each with its own contract test.
- FIT verification against a locally generated JWKS: wrong `aud`, wrong environment, expired, wrong `alg`, unknown `kid`.
- The token write rule under concurrent writers, including an older token arriving after a newer one.
- Pairing: expired, reused, wrong secret, installation bound elsewhere, user without integration rights.
- Merge guard: moved head, already merged, 202 then pending.

## 14. Open decisions

1. **Tool names:** `pull_request_*`, following `tracker_*`. Recommended.
2. **GitHub on the port:** later and optional; `gh` stays the GitHub path. Recommended.
3. **Merging on by default**, per-integration off switch — consistent with Azure. Recommended.
4. **`draft` defaults to true** on create — consistent with Azure. Recommended.
5. **One installation, one company.** Recommended: no multi-company proof exists on Bitbucket.
6. **Reinstall rebinds through a new pairing** rather than automatically by workspace UUID. Recommended: it costs the admin one click and keeps the proof fresh.
7. **Token mode visible in the SaaS UI** as the secondary path, as GitHub PAT mode is. Recommended.
8. **No webhooks in token mode** (sweep-only gates). Recommended; revisit if gate latency is a complaint.
