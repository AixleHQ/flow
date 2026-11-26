# Integrations chosen per session

**Status:** design (task #295), round 2: updated by the review decisions of 2026-11-26 (Alex). Nothing here is built.
It is implemented as **one task**; §8 gives the order inside it.

## 1. Why

A project sees at most one active integration of a provider per scope (its own, and the company's), and the
tools pick it themselves. For Coder, `Coder::IntegrationService#ensure_only_active!` refuses a second
integration in a scope, and `InternalTools::Concerns::CoderResolver` takes the project's integration, else
the company's. The agent cannot name one. So a customer cannot keep the integration its Coder runners use
(#284) apart from the one agents use, or give one workflow one Coder account and another workflow a
different one.

Wanted: (1) several integrations of a provider in one scope; (2) the integrations a session may use are
set explicitly, on a workflow, on an interactive session, and wherever else a session starts; (3) every
tool that acts through an integration takes the integration's id, Coder first; (4) the agent is told the
list (name, provider, id).

## 2. How integrations are resolved today

Read from `develop`. "Several" is whether the model already allows more than one in a scope.

| Provider | Several? | Picked by | Entitlement to a session |
|---|---|---|---|
| GitHub, GitLab, Bitbucket | yes | the repository (`repositories.integration_id`); `pull_request_*` read `repository.integration` | the repository is attached to the session (workflow `base_repository_ids`, step, run, session) |
| Azure DevOps | yes | repository tools: the repository. Build tools: `integration_id` param (`AzureDevopsContext#resolve_integration!`), listed by `azure_devops_list_connections` | repository tools: attached repository. Build tools: **none**, any connection of the project (`verify_project_ownership!` only) |
| Jira, Linear, YouTrack | yes | `ProjectTracker` (`tracker` handle from `tracker_list`); a tracker-started run pins its tracker | `ProjectTracker` attached to the project, not to the workflow |
| Slack, Teams | yes | the run's origin (`Chat.origin`), else `Slack::InstallResolver` (project install, else the company's earliest); Teams via `Chat::TargetResolver`, channels via `Chat::ChannelAccess` | none: every session of the project |
| Coder | **no** (`ensure_only_active!`) | `CoderResolver`: project's, else company's | none: every session of the project |
| AWS OIDC | yes | `aws_oidc_roles` (child of the integration) | **explicit**: `Workflow#base_aws_oidc_role_ids`, `Step#aws_oidc_role_ids`, workflow steps only |
| Insights | n/a | company-level telemetry, no tools | n/a |

Two gates read the connected set and not the session: `Tools::Context#connected_providers` (the
`requires_integration` / `inject_when` check on every MCP request) and `Tool.active_integration_providers`
(pickers). Both answer "does the project have an active integration of this provider".

Consumers of "the Coder integration" outside the tools: `Coder::LockService.release_all_for_session` (already
walks every active Coder integration of the scope), `Coder::DeadWorkspaceReaper` (every active one), and
`Runner#integration` (an explicit FK, so #284 already names its integration). `Coder::LockService` treats a
workspace reached through two integrations as one machine (`MakeCoderWorkspaceLocksExclusive`). Nothing in
the code needs one Coder integration per scope; the rule is only a check at connect time.

The closest precedent is AWS OIDC roles: production access, attached explicitly to a workflow and a step,
not covered by `inherit_all_project_resources` (`SessionConfigResolver#resolve_aws_oidc_role_ids`). This
design reuses its storage and editing path.

## 3. Approach

**Entitlement is a set of integration ids on the session.** A session's *integration set* is:

1. the integrations attached explicitly (workflow, step, interactive/API session), plus
2. the integrations of the repositories attached to it (derived, never attached twice), plus
3. the *origin* integration of the run (the Slack or Teams install that started it, the tracker's
   integration), so a reply to the thread always works.

The set is resolved once, when the session is built, by `SessionConfigResolver` (new `integration_ids`
key, next to `repository_ids`), and stored on the session in a `session_integrations` join table
(same shape as `session_tools`, `id: false`). Tools and gates read `session.integrations`, not the project.
A session gets only those integrations; a tool called with an id outside the set is refused as
"not attached to this session", the way `resolve_repository!` refuses a repository.

**Every tool that acts through an integration not already determined by a repository takes `integration_id`.**
The Azure build-tool pattern ("list, then pass an id") is the model, with one softening for providers that
had no id before (see §6, decision 4): the id may be omitted only when the set holds exactly one integration of that
provider. With two or more, omitting it is an error that lists the candidates.

**Alternatives considered**

- *Keep resolving from the project; add only `integration_id` to tools.* Meets (3) but not (2): a
  workflow could not be kept away from an account. Rejected.
- *Attach by provider ("this workflow uses Coder") and let the tool pick.* Brings back the arbitrary pick
  the task wants gone. Rejected.
- *A `workflow_integrations` / `step_integrations` pair of tables.* The `workflow_resource_links` and
  `step_resource_links` tables already hold ordered, per-owner, FK-cascading lists through `ResourceLink`
  and `ResourceLists`; AWS roles were added as a column there. A new column is less code and follows the
  pattern. Chosen.
- *Store the set in `terminal_sessions.session_config` jsonb.* Loses the FK cascade and the tenant
  validation. `session_repositories` / `session_tools` are join tables. Chosen: join table.

## 4. Data model changes

1. **Coder: several integrations in one scope, identified by URL + account + prefix** (§4.1).
2. **Attachment on workflows and steps:** migration adds `integration_id` (nullable bigint, FK to
   `integrations` `on_delete: :cascade`, partial index `WHERE integration_id IS NOT NULL`, unique
   `(workflow_id, integration_id)` / `(step_id, integration_id)` partial index) to `workflow_resource_links`
   and `step_resource_links`, and rebuilds the `*_one_resource` check constraint to count it in
   `num_nonnulls(...)`. In code: `ResourceLink::COLUMNS` gains `integration_ids: :integration_id`,
   `belongs_to :integration, optional: true`; `Workflow` gets `base_integration_ids`, `Step` gets
   `integration_ids`, both via `resource_lists`.
3. **Ownership validation:** `validates :base_integration_ids, tenant_ids: { model: Integration, ... }` on
   `Workflow` and `Step`, following `base_aws_oidc_role_ids` and `base_repository_ids`. `TenantScope.owned`
   already has an `Integration` rule (company-wide and the project's own). A `System` workflow cannot hold
   integrations (it has no project): validate absence.
4. **On the session:** table `session_integrations (terminal_session_id, integration_id)`, both FKs
   cascading, unique pair index. `TerminalSession has_many :session_integrations; has_many :integrations,
   through:`. `SessionService#attach_resolved_resources` sets
   `session.integrations = scoped_resources(Integration, config[:integration_ids], session)`; add
   `Integration.visible_for_project` handling to `scoped_resources` (it already exists). Company-wide
   Integrations stay attachable (a project may use the company's Coder).
5. **Per-run override:** none (accepted in review). `workflow_runs` gets no column (unlike `repository_ids`); see §11.
6. **Naming:** an integration needs a name the agent and the user can tell apart. Coder names are generated
   (`"Coder <username>"`), so two accounts on two deployments can read alike. `IntegrationResource` and the
   agent list show `name`, provider and id, and for Coder the host of `coder_url` as well. Making the name
   editable is deferred (§11).

### 4.1 Coder integration identity and the workspace pool

**Identity.** A Coder integration is identified by `(coder_url, Coder account, machine_prefix)`; the account is
`coder_user_id`. In `Coder::IntegrationService`:

- `ensure_only_active!` and its three calls (`create`, `replace_token`, `test`) are removed, with the
  "at most one" wording in the class comment and the test "a project cannot get a second active Coder
  connection".
- `existing_for(url, info)` additionally compares the prefix (`machine_prefix.presence`; blank is its own
  value). The same URL and account with **another** prefix is a **new** row. The same triple is a
  **renewal**: only the token (and the identity fields `apply` already refreshes) is replaced.
- `create` no longer merges the submitted `default_template` / `machine_prefix` / `lock_ttl_minutes` into a
  row it found. They apply only to a new row; a renewal keeps the row's settings (edited through
  `update_settings`, as the UI already offers). This removes the silent rewrite of another integration's
  prefix and template that `existing_for` plus the merge do today. The connect form says "Renewing keeps the
  existing pool settings".
- `replace_token` keeps its "already has another connection here" check, now over the triple, as a guard.
- **Pool overlap guard.** A blank prefix means "every workspace the token owns". For one URL and account, a
  blank prefix cannot coexist with another integration (`create` and `update_settings` refuse with "set a
  prefix on the other integration first"), because the pools would overlap and one machine would be
  reachable through two integrations. Two non-blank prefixes never overlap, see below. `update_settings`
  also refuses a prefix change that makes the triple equal to another row's. Both checks run in a
  transaction holding `company.lock!`: integrations per company are few, this runs only on connect and edit,
  and no column holds the triple (the credentials are encrypted), so a unique index is not possible.

**The pool is matched by a pattern, not by `start_with?`.** Today `Coder::WorkspaceService#list` keeps
workspaces whose name `start_with?(prefix)`, so pool `aixle` also takes `aixle-r-1a2b3c4d`, which belongs to
pool `aixle-r`. New: `Coder::Pool.matches?(prefix, name)` (one class, one regexp, used by the allocator, the
`DeadWorkspaceReaper` and `WorkspaceService#list`) with the format

    <prefix>-<suffix>      suffix = one segment of [0-9a-z], no hyphen

`Allocator#generate_workspace_name` produces `<prefix>-<8 hex>` (as now; `aixle` when the prefix is blank).
A blank prefix still lists everything, as today, and is allowed only as the sole integration of its URL and
account. Because the suffix has no hyphen, `aixle` does not match `aixle-r-1a2b3c4d` (suffix `r-1a2b3c4d`),
while prefix `aixle-r` does. A prefix that ends in a hyphen or has characters outside `[0-9a-zA-Z-]` is
refused on save (`create` and `update_settings`), so the pattern is unambiguous.

**Existing workspaces that do not follow the pattern** (made by hand, e.g. `aixle-prod-a-b` under prefix
`aixle`): they were pool members through `start_with?` and would silently leave the pool. Nothing is deleted
or stopped; they stop being allocated and reaped. So that this is a decision and not a surprise:

- A read-only rake task `coder:audit_pools` (new, `lib/tasks/coder.rake`) lists, for every active Coder
  integration, the workspaces that match `start_with?(prefix)` but not the pattern, and the integrations of
  one URL and account whose prefixes nest. **Production is checked with it before release**, and the release
  waits while the list holds a workspace someone still uses.
- The fixes are data-only: set the integration's prefix to a longer one that matches (`aixle-prod` matches
  `aixle-prod-001`), or rename the workspace in Coder.
- Lock and quarantine rows are keyed by workspace name inside the integration, so a workspace leaving the
  pool keeps its row until it expires; `LockService.release_all_for_session` needs no change.

## 5. Interface changes

### 5.1 Setting the set

- **Workflow builder:** a new "Integrations" list on the workflow's base resources (`BaseResourcesTab.tsx`)
  and on the step editor (`SessionEditorPanel.tsx`), next to AWS roles; draft handling in `builderDraft.ts`;
  `WorkflowResource` / `StepResource` expose `baseIntegrationIds` / `integrationIds`;
  `Api::V1::Projects::Workflows::AggregatesController` and `StepsController` permit them
  (follow `aws_oidc_role_ids` there). Choices are the project's visible integrations in a provider that has
  tools (`Integration.visible_for_project(project)` filtered by the attachable providers, §5.3).
- **Personal MCP (Aixle Builder):** `create_workflow`, `update_workflow`, `create_workflow_step`,
  `update_workflow_step`, `get_workflow`, `validate_workflow` take and return the lists;
  a new `list_integrations` personal tool (sibling of `list_aws_oidc_roles`) returns id, name, provider,
  scope, status. `validate_workflow` warns when a step's instructions or attached tools need an integration
  of a provider the workflow has none of.
- **Interactive session:** `SessionService.create_and_start` and `Api::V1::TerminalSessionsController`
  accept `integration_ids`. The new-session form (`NewPage.tsx`, `NewSessionDrawer.tsx`,
  `RunWorkflowDrawer.tsx` shows the workflow's set read-only) gets the same picker. When the parameter is
  omitted, the session gets **no integrations**, interactive and API sessions alike (review decision).
  The new-session form preselects a default, so people in the UI see the choice: the project's Coder
  integration, its Slack or Teams install and its Azure DevOps connections (the backfill's rule, §7). API
  clients pass `integration_ids`; the API docs and the CHANGELOG announce it.
- **Standalone session resolution:** `SessionConfigResolver` for a standalone session reads
  `session.integration_ids` (like `config_item_ids` there); for a workflow step it is
  `workflow.base_integration_ids + step.integration_ids`, additive, **not** widened by
  `inherit_all_project_resources` (same rule as AWS roles: access to an external account is never implied).
- **Other session starts**, each ends in the workflow or the form above: Slack and Teams runs, tracker
  runs, pull-request and webhook triggers, board column triggers and schedules all start a workflow, so the
  workflow's set applies, plus the origin integration (§3.3). The Aixle Builder session
  (`AixleBuilderController`) gets no integrations: it uses personal tools pinned to the project. Meta
  workflow sessions use the workflow path.
- **Versions and templates:** `Versions::Snapshots::Workflow`, `versionSchemas.ts`, `versionHistory.ts`,
  `WorkflowDuplicator` (+ `DependencyCopier`), `Templates::Exporter` / `Installer` / `SetupChecklist` and
  `ProjectMove::Preflight` all carry `aws_oidc_role_ids` today; each gets the same for integrations.
  Integrations are not exported by value: an exported template records "needs a Coder integration" in the
  setup checklist, and the installer leaves the list empty (the importer attaches their own). Duplicating
  inside a project keeps the ids; moving a workflow to another project drops them and lists them in the
  preflight, as it does for roles.

### 5.2 What the agent is told

A new `ContextBuilders::Integrations` (registered next to `Resources`), applicable when
`session.integration_ids` is present, renders in `<available-resources>`:

```
## Available Integrations
| ID | Name | Provider | Notes |
Pass the integration **ID** as `integration_id` to tools that act through an integration.
```

Notes: Coder shows the host and the default template; Azure DevOps the organization; Slack and Teams the
workspace; repositories keep their own table. No credentials, no URLs with tokens. The session's
integration set is also what `azure_devops_list_connections` returns (it stays; it adds the capability
profile) and what the new error message lists when an id is missing or wrong.

### 5.3 Tools and gates

- **Gates.** `Tools::Context#connected_providers` becomes session-aware: with a session it returns the
  providers of `session.integrations` (plus the derived-from-repository ones, plus trackers/chat/PR
  capabilities derived from them as today); without a session (pickers, `Tool.active_integration_providers`,
  project pages) it stays project-wide so a tool can still be attached. The injection rules
  `coder_integration_connected` and `azure_integration_connected` keep their names and now mean
  "this session holds one". This is where #290 meets this task: #290 attaches tools explicitly instead of
  injecting them because an integration is connected; whichever lands second reuses the same predicate
  (`ctx.connected?(provider)`), so there is no conflict, but the order in §8 puts the session set first.
- **Coder tools** (`coder_allocate_machine`, `coder_ssh_exec`, `coder_prepare_repo`, `coder_job_status`,
  `coder_release_machine`): `CoderResolver` is rewritten. It reads `params[:integration_id]`, resolves it
  with `session.integrations.where(provider: :coder, status: :active)`, and raises `NotConfiguredError`
  with the candidate list for none / unknown / ambiguous. Each tool schema gains `integration_id`
  (optional when exactly one Coder integration is attached, as in §3). `workspace_name` is only unique inside
  one integration, so the lock checks (`held_by_session?`, `release_owned`) are already per-integration and
  stay so. `Coder::LockService.release_all_for_session` keeps walking every Coder integration of the scope
  (teardown must release whatever the session holds, attached or not).
- **Azure DevOps:** the build tools' `resolve_integration!` additionally requires the id to be in
  `session.integrations` (today any connection of the project passes). Repository tools unchanged.
  `azure_devops_list_connections` lists `session.integrations` of that provider.
- **Slack / Teams (`chat_*`):** `ChatContext` / `SlackContext` resolve the install from the set:
  the origin install if the run came from Slack; otherwise the explicit optional `integration_id`;
  otherwise the sole attached install of that provider; otherwise an error listing them. For a named
  `conversation`, `Chat::ChannelAccess.install_for` must return an install inside the set.
  `Slack::InstallResolver` stays as the resolver for non-session callers (`HelpResponder`,
  `RunFailureNotifier`): those are platform notifications, not agent tools, and are untouched.
- **GitHub / GitLab / Bitbucket:** no new parameter. The repository identifies the integration, and the
  repository's own entitlement is the session's attached repositories. The `*_user_token` tools act as a
  person on the repositories' hosts and stay as they are; their `requires_integration` now reads the set.
- **Trackers:** unchanged. `ProjectTracker` is already an explicit, handle-based attachment, and a
  tracker-started run pins its tracker; moving tracker entitlement onto workflows belongs with #290.

Provider list for attachment (`Integration::ATTACHABLE_PROVIDERS`, one constant used by the pickers, the
validators and the builder): `coder`, `slack`, `teams`, `azure_devops`. GitHub, GitLab and Bitbucket are
reached through repositories, trackers through `ProjectTracker`, so attaching them would be a second
switch for the same thing. `aws_oidc` stays on roles; `insights` has no tools. The constant is the single
place to extend.

## 6. Decisions and assumptions

1. **Attach only providers whose tools take an integration directly** (Coder, Slack, Teams, Azure DevOps;
   trackers are out, #296 covers attaching them).
   Source: §2, repository-based providers are already entitled through `base_repository_ids`.
2. **Storage in `workflow_resource_links` / `step_resource_links`**, not new tables. Source: the AWS role
   precedent and `docs/architecture/implementation-patterns.md` (Tenant References).
3. **Not inherited by `inherit_all_project_resources`.** Source: AWS precedent; an integration is access to
   an external account.
4. **`integration_id` optional when exactly one integration of the provider is attached** (accepted in review,
   as the tracker tools take `tracker` only when there are several). Without this,
   every existing Coder prompt and skill that calls `coder_allocate_machine` with no arguments breaks on
   rollout. Azure build tools stay strictly required, as today.
5. **Derived sets:** repository integrations and the origin integration are always in the set. Source:
   the repository table already attaches them; requiring a second attachment would be a trap.
6. **Omitted `integration_ids` means none**, interactive and API sessions alike. Source: review decision 2.
   The form preselects a default; API clients pass ids; announced in the CHANGELOG.
7. **No per-run override** (`workflow_runs`), accepted in review. Add one if a customer needs "run this
   workflow against account B" (§11).
8. **Company-wide integrations are attachable** to a project's workflows. Source: `TenantScope.owned`
   already treats them as owned by the project.
9. **Disconnecting an attached integration** removes its links (FK cascade); a running session keeps its
   `session_integrations` row until the integration row goes, and the tool then fails with the usual
   "not connected" error. `Integration#destroy` is unchanged (`runners` stay `restrict_with_error`).
10. **Coder identity is URL + account + prefix**; renewal replaces only the token; connecting never rewrites
    another integration's settings; the pool is matched by a pattern (§4.1). Source: review decision 6.
11. **One implementation task**, no split (review decision 7).

## 7. Existing workflows and sessions

No temporary fallback lives in code: `Integrations::Cutover` and the "created before the cutover" rule in the
gates are dropped. The gates read `session.integrations` and nothing else. Existing data gets its set from
**one idempotent backfill**, `Integrations::Backfill`, a plain Ruby service in `app/services/integrations/`,
run by a data migration at release and, once more, by a rake task after the rollout (below).

- **Workflows.** Every non-system workflow gets what it gets today, regardless of #290 and of whether the
  workflow has that provider's tools:
  - the project's active Coder integration (the company's only if the project has none: the
    `CoderResolver` pick, so behaviour is kept);
  - its Slack or Teams install (the `Slack::InstallResolver` pick, per messenger);
  - every active Azure DevOps connection of the project (build tools reach all of them today).

  Nothing is attached for a provider the project has no integration of. Steps are not backfilled (the
  workflow list is additive). Re-running adds nothing already linked.
- **Running sessions.** Sessions alive at the deploy get `session_integrations` rows in the same data
  migration: workflow sessions the workflow's backfilled set, plus their repositories' integrations, plus
  their origin integration (the run's Slack or Teams install, the tracker's integration); standalone
  sessions the same default the form preselects. Finished sessions get nothing: nothing reads them.
- **Sessions created during the rollout.** Between the migration and the last old pod stopping, old code
  creates sessions without writing the set while new code already gates by it. No code in the gates covers
  this. The release runs `bin/rails integrations:backfill_sessions SINCE=<release start>` a second time
  **after the rollout is complete**. It gives every session created since then that has no
  `session_integrations` row the set of the running-session rule above. Sessions that new code created
  have rows and are skipped. The one it can get wrong is a session new code created in that window with an
  explicitly empty set; the window is minutes and the result is a set the user could have chosen, so it is
  accepted. A tool call in such a session before the second run says "not attached to this session" and
  works after it. The release checklist in the PR names both steps.
- **Behaviour changes for the CHANGELOG:** a new integration connected after the deploy is not usable by
  existing workflows until attached; an API or interactive session that passes no `integration_ids` has no
  integrations; a second Coder account can be connected.
- Slack/Teams runs are unaffected (origin integration), and `HelpResponder` / `RunFailureNotifier` are
  untouched.

## 8. Order inside the task

One task. The order inside it keeps behaviour unchanged until attaching works in the builder, the personal
MCP and the new-session form:

1. **Model and storage:** migration (links columns + constraint, `session_integrations`), `ResourceLink`,
   `Workflow` / `Step` lists, tenant validation, `ATTACHABLE_PROVIDERS`, `TerminalSession#integrations`.
2. **Resolver and session build:** `SessionConfigResolver#resolve_integration_ids` (+ breakdown),
   `SessionService` attach, API/web params for standalone sessions (omitted = none).
3. **Attaching, end to end:** builder UI, personal MCP (`list_integrations` and the workflow tools),
   new-session form with its preselected default, versions, templates, duplicator, project move.
4. **Backfill:** `Integrations::Backfill`, the data migration, `integrations:backfill_sessions`, the release
   checklist (§7). Nothing reads the set yet.
5. **Agent context:** `ContextBuilders::Integrations`.
6. **Gates:** session-aware `Tools::Context#connected_providers`; Azure build tools check the set. This is
   the switch that changes behaviour, and it comes after 3 and 4.
7. **Coder:** identity rules and `Coder::Pool` (§4.1), `coder:audit_pools`, `CoderResolver`,
   `integration_id` on the five tools, wording on the Coder connect page.
8. **Slack/Teams** tools resolve from the set and accept `integration_id`.
9. **Docs:** user guide pages (Using Flow → workflows, integrations), API docs, `docs/design` status, CHANGELOG.

Before release, `coder:audit_pools` runs on production and its list is handled. Rollback: reverting step 6
restores the project-wide gate; the data added by steps 1 to 4 is inert.

## 9. Testing

- `Coder::Pool` and `Coder::IntegrationService`: same account + another prefix is a new row; same triple
  renews and leaves the row's settings alone; blank prefix refused next to another integration of the account;
  `aixle` does not match `aixle-r-1a2b3c4d`, `aixle-r` does; hand-made names fall out of the pool;
  `coder:audit_pools` output.
- Models (`test/models`): `ResourceLink` with integrations, `Workflow` / `Step` list validation (foreign
  company and foreign project rejected, system workflow rejected), `Coder::IntegrationService` with two
  active integrations (replace the "cannot get a second" test with "two accounts coexist; same account
  renews").
- Services: `SessionConfigResolver` (workflow + step additive, not inherited, derived repository and origin
  integrations, standalone, breakdown), `SessionService` attach, `CoderResolver` (none / one / many /
  foreign id / inactive), `Tools::Context` session-aware vs project-wide, `Integrations::Backfill` (workflows and running
  sessions; idempotent; only providers that exist; the second session run skips sessions that have rows).
- Tools: each Coder tool with `integration_id`; Azure build tool refuses a connection outside the set;
  chat tools with two installs (origin wins, explicit id, ambiguous error).
- Requests (`test/integration`): workflow aggregates and steps accept and return the lists, a foreign id
  is a 422; terminal sessions API with `integration_ids` and with it omitted (no integrations).
- Frontend: `BuilderPage` draft, `NewSessionDrawer` picker, `versionSchemas` (follow the AWS role tests).
- Contexts: `ContextBuilders::Integrations` rendering, no secrets in output.

## 10. Edge cases and risks

- **Same workspace through two integrations:** the exclusive lock index already treats it as one machine; an
  agent allocating through both sees the second `LockNotAcquired`. Documented in the Coder tool descriptions.
- **Two Coder integrations with the same account name:** the id, not the name, is the key; the context
  table shows the host to tell them apart.
- **Integration goes `error` or `inactive` while attached:** stays attached, tools say which integration
  failed; the builder shows the status.
- **A workflow attaches an integration a later editor cannot see** (a company-wide one, member of another
  project): the validator checks ownership, not the editor's visibility, as for `base_repository_ids`.
- **Gate cost:** `connected_providers` is called per tool definition on every MCP request; the session set
  is one query memoised on the context, no worse than today.
- **Prompt text that says "the Coder integration":** skills and templates shipped by the platform
  (`Templates`, BMAD) are checked in step 7 so they still work with the optional id.
- **Overlapping pools:** a prefix that begins another no longer shares machines (pattern match). A blank
  prefix is refused next to another integration of the same account.
- **Workspaces leaving the pool** (§4.1): audited before release, never deleted by this change.
- **Rollout window** (§7): sessions created by old pods get their set from the second backfill run.
- **Runner pools (#284):** `Runner#integration` already names its integration; with two integrations a
  customer can connect one to the runner and attach the other to workflows. Nothing in the runner design
  changes.

## 11. Deferred

- A per-run override of the set (`workflow_runs`), and a trigger-level choice of integration.
- Editing an integration's name; today it is generated for Coder.
- Moving tracker entitlement onto workflows (belongs with #296 and #290).
- Creating a company-wide Coder integration from the UI (`create_coder` always passes the project).
- Attaching GitHub, GitLab and Bitbucket integrations without a repository (e.g. for a future tool that
  acts on an account rather than a repository).
