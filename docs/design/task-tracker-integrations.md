# Task tracker integrations — technical design

Status: **Proposal; decisions 1–16 agreed 2026-09-30; one open question (§13.2)**
Date: 2026-09-30
Related: PR #271 (YouTrack integration, unmerged) and its two design documents,
`integration-abstractions-tech-design-v1.md` and `youtrack-integration-tech-design-v6.md`;
[`azure-devops-integration.md`](./azure-devops-integration.md), the only tracker-like integration
already in the tree.

## 1. Goal and product shape

A project can connect one or more external task trackers (YouTrack, Jira, Linear, GitHub
Projects, Azure Boards). A connected tracker gives the project three things:

1. **Trigger events** — a workflow can start when an issue is created, changes status (moves to
   a column on the tracker's board), is assigned, or gets a comment.
2. **Agent tools** — read, search, create, update, transition, assign and comment on issues.
3. **Run affinity** — a run started by a tracker event knows its tracker and issue, and has the
   tracker tools without anyone attaching them.

Every tracker gets the **same** event vocabulary and the **same** tool set. Only connection setup,
the HTTP client and event parsing are specific to a provider. Because of that, a workflow or
template written against one tracker runs against another, and moving a project from one tracker
to another does not change its workflows (§8).

Out of scope for this design: importing or mirroring issues into the Aixle board; keeping Aixle
board columns and tracker statuses in sync; polling or gap reconciliation; provider-specific tools;
attachments, issue links and deletions. §12 says where each would attach later.

## 2. Decisions

| Area | Decision |
|---|---|
| Layers | Three records: **connection** (`Integration` — instance, credentials, identity), **project tracker** (one external project/team mapped into one Aixle project), **subscription** (how events reach us). A connection can serve many external projects and many Aixle projects. |
| Several trackers | Allowed. A project has at most one *primary* tracker. Each tracker is `read_write` or `read_only`. |
| Events | Normalized `tracker.*` types, the same for all providers: `tracker.issue.created`, `tracker.issue.status_changed`, `tracker.issue.assigned`, `tracker.comment.created`. |
| Event trust | A webhook is a **notification**. The payload is trusted only for IDs and change hints. Issue data is re-read through the API with our own credentials before anything is matched or shown to an agent. |
| Triggers | One new trigger kind, `tracker`. The binding names a project tracker, or none for "any tracker in this project". Filters run on normalized event data through the existing `TriggerFilter`. |
| Aixle-caused events | Attributed to the run that made the change, through the write ledger. A per-binding `aixle_changes` setting (`ignore` by default, `other_workflows`, `always`) enables chaining, and hard depth and per-issue limits stop loops (§6.6). |
| Subject | Adds `find_or_create_task`, which becomes the default for tracker triggers. It reuses the task already linked to the issue, or creates one and links it. |
| Tools | One global `tracker_*` set of code-first tools. An optional `tracker` argument selects the target. Resolution is deterministic and never falls back to "the first row" (§7.2). |
| Tool availability | Attachable from the picker when the project has an active tracker. Injected automatically into runs that a tracker event started. |
| Provider seam | `Trackers::Provider`, one class per provider, registered in an explicit hash. The seam is the normalized `Notification`, not the HTTP request, so providers whose events arrive through an existing receiver (GitHub App, Azure Service Hooks) plug in without the tracker ingress. |
| Connection lifecycle | Connect, reconnect (rotate credentials in place), verify, disconnect (soft). Integration IDs, webhook URLs and trigger bindings survive credential rotation. |
| Issue ↔ task identity | Generic `external_resources` links keyed by the external system's identity, not by connection. They survive reconnects and second connections. |
| Platform integrations | Azure DevOps and GitHub are platforms, not trackers: one connection serves code hosting, pull requests, CI *and* boards. The tracker port is one capability they implement over their existing connection, client and event receiver; their repository/PR/CI tools stay provider-specific (§9). |
| Provider order | Azure Boards (with the core) → Jira → GitHub Projects → Linear → YouTrack (§12). PR #271 stays open; its hardened client and connect verification are copied over in the YouTrack phase rather than merged. |

## 3. What already exists

This design reuses, rather than re-derives:

- **`Integration`** (`app/models/integration.rb`) already belongs to a company, optionally to a
  project, and exposes `company_wide` and `visible_for_project`. The enum carries a `linear` value
  with no code behind it. `docs/user-guide/integrations.md` §Linear describes it as supported, and
  it is not.
- **Triggers.** `TriggerBinding` + `TriggerEngine` provide the outbox (`TriggerEvent` with a unique
  `dedup_key`), per-binding launch dedup (`TriggerDispatch`), cooldown, the `none` /
  `existing_task` / `create_task` subject policies resolved inside the dispatch lock, and
  `TriggerFilter` (dot-paths; `eq`, `in`, `contains`, `regex`, …). `WorkflowTriggers::Creator` is
  the one entry point shared by the web API, the personal MCP and the template installer.
- **Tools.** Code-first `InternalTools` with the `tool do … end` DSL: `requires_integration`,
  `availability`, `user_attachable`, `tags`, and `inject_when` over the closed
  `Tools::InjectionRules` vocabulary, evaluated per session in `TerminalSession#available_tools`.
  `InternalTools::Base#workflow_run` reaches the run's `shared_context`.
- **Azure DevOps**, the tracker precedent already in the tree. Its design took several positions
  this one adopts:
  - work-item tools require an explicit target and never pick "the first connection"
    (`app/services/internal_tools/concerns/azure_devops_context.rb:48`);
  - `azure_devops_list_connections` is the discovery tool;
  - one connection covers several Azure projects (`Integration#azure_project_ids`);
  - subscriptions are created through the provider API (`AzureDevops::SubscriptionService#ensure_all!`);
  - a delivery is deduplicated before it is acknowledged, and its payload is treated as a
    notification to re-read authoritative state (`app/controllers/webhooks/azure_devops_controller.rb:18`);
  - creates and comments go through an idempotent operation ledger (`azure_devops_operations`).
- **PR #271 (YouTrack)** stays open while this design is built on its own branch. YouTrack is the
  last phase (§12), and these parts are copied over then:
  the SSRF-hardened client transport (DNS pinning, bounded
  responses, no redirects), connect-time identity and project verification, the operator setup
  documentation, and the `external_resources` idea. Not adopted: one connection per external
  project, provider-named events and tools, first-row integration selection, payload text treated
  as state, and adapters branching inside the generic slug ingress.

## 4. Concepts and data model

### 4.1 Three layers

```text
Integration (connection)            e.g. "Acme YouTrack", company-wide
  instance, credentials, identity (the bot user)
  │
  ├── TrackerSubscription           one per (connection, external project) — or one per
  │     endpoint URL, secret,       connection when the provider sends org-wide webhooks
  │     strategy manual|api, expiry
  │
  └── ProjectTracker                one per (Aixle project, connection, external project)
        handle "youtrack-app", primary?, read_write|read_only,
        status field + category mapping
          │
          ├── TriggerBinding.project_tracker_id   (null = any tracker in the project)
          └── ExternalResource links on board tasks (keyed by external identity, not by tracker)
```

A company-wide connection to one YouTrack instance can feed project **Alpha** from YouTrack
project `APP` and project **Beta** from `OPS` and `APP`. Credentials are stored once and rotated
once.

### 4.2 Tables

```text
project_trackers
  id
  project_id           FK projects, NOT NULL
  integration_id       FK integrations, NOT NULL      -- must be visible_for_project(project)
  provider             varchar NOT NULL               -- copy of integration.provider
  external_scope_id    varchar NOT NULL               -- YouTrack project DB id, Jira project id,
                                                      -- Linear team id, GitHub project node id,
                                                      -- Azure project GUID
  external_scope_key   varchar                        -- "APP"; the issue-key prefix, where one exists
  name                 varchar NOT NULL
  handle               varchar NOT NULL               -- what agents and triggers call it
  primary              boolean NOT NULL DEFAULT false
  access               varchar NOT NULL DEFAULT 'read_write'   -- read_write | read_only
  status               varchar NOT NULL DEFAULT 'active'       -- active | error | detached
  settings             jsonb NOT NULL DEFAULT {}      -- status_field, status category overrides,
                                                      -- default issue type, field deny list
  timestamps
  UNIQUE (project_id, integration_id, external_scope_id)
  UNIQUE (project_id, handle)
  UNIQUE (project_id) WHERE primary

tracker_subscriptions
  id
  integration_id            FK integrations, NOT NULL
  external_scope_id         varchar                  -- NULL = connection-wide (Jira, Linear)
  strategy                  varchar NOT NULL         -- manual | api
  endpoint_token            varchar NOT NULL UNIQUE  -- routes POST /webhooks/trackers/:token
  secret                    encrypted                -- shared token, HMAC secret or basic-auth password
  provider_subscription_id  varchar                  -- api strategy
  status                    varchar NOT NULL         -- pending | active | failing | expired | disabled
  expires_at, last_event_at, last_error
  UNIQUE (integration_id, external_scope_id)

tracker_deliveries
  id
  tracker_subscription_id   FK, NOT NULL
  dedup_key                 varchar NOT NULL
  notification              jsonb NOT NULL           -- IDs and change hints only; never text
  status                    varchar NOT NULL         -- received | processed | skipped | failed
  detail                    jsonb NOT NULL DEFAULT {}
  timestamps
  UNIQUE (tracker_subscription_id, dedup_key)

external_resources
  id
  board_task_id    FK board_tasks ON DELETE CASCADE, NOT NULL
  kind             varchar NOT NULL                  -- "tracker_issue"
  provider         varchar NOT NULL
  instance         varchar NOT NULL                  -- the provider's instance identity (§5.3)
  external_id      varchar NOT NULL                  -- stable issue id, never the readable key
  data             jsonb NOT NULL DEFAULT {}         -- key, url, created_via (trigger|tool),
                                                     -- project_tracker_id (diagnostic only)
  timestamps
  UNIQUE (board_task_id, kind, provider, instance, external_id)
  INDEX  (kind, provider, instance, external_id)

trigger_bindings
  + project_tracker_id   FK project_trackers, NULL, ON DELETE RESTRICT
  + aixle_changes        varchar NOT NULL DEFAULT 'ignore'   -- ignore | other_workflows | always (§6.6)
  + tracker_handoff      jsonb NOT NULL DEFAULT {}           -- start / success / failure statuses (§6.9)

tracker_operations          -- every tracker write: idempotency (§7.4) + causality (§6.6)
  integration_id, operation, operation_key, request_digest, state, target_kind, target_id,
  result, terminal_session_id, user_id,
  workflow_run_id, workflow_id, chain jsonb,         -- who made the write
  issue_id, change jsonb, result_ref                 -- what it changed (field/to, created comment/issue id)
  UNIQUE (integration_id, operation, operation_key)
  INDEX  (integration_id, issue_id, created_at)
```

Notes:

- `kind`, not `type`: a `type` column switches ActiveRecord into single-table inheritance.
- `project_tracker_id` uses `ON DELETE RESTRICT`, not `nullify`. Nulling would silently widen a
  binding from "this tracker" to "any tracker". A project tracker is detached, never hard-deleted,
  while bindings reference it.
- The subscription is a separate table instead of a reused `WebhookEndpoint`. It follows the
  Azure `AzureDevopsSubscription` + `AzureDevopsDelivery` precedent: a subscription has a
  provider-side lifecycle (registration, expiry, probation), and the generic slug ingress stores
  raw bodies, which this design deliberately never does.

### 4.3 Connection lifecycle

`Trackers::ConnectionService` has four operations, each running through the provider's `verify!`:

- **connect** — create the `Integration`, verify, and store identity (`bot_user_id`, `bot_login`).
- **reconnect** — replace credentials **in place** and re-verify. The integration ID, every
  subscription URL, every project tracker and every binding survive. A permanent token whose owner
  left is the common case, and today it would cost every trigger. If the identity changes, the UI
  says so, because mention detection and own-change suppression key on it. Each project tracker is
  re-checked, and one whose external project the new credentials cannot see goes to `error`.
- **verify** — "Test connection". Sets `active` or `error` with a sanitized message. A failed
  connection can later become active; it does not have to be recreated.
- **disconnect** — soft. Unregister `api` subscriptions at the provider, disable subscriptions,
  wipe credentials, and set the integration `inactive`. Its project trackers go to `detached`,
  and bindings on them are disabled. Links and delivery audit rows stay. Reconnect restores the
  integration. Hard delete is a separate, explicit action that is refused while bindings reference
  its trackers.

A **project tracker** is created from a visible connection: pick the connection (or create one),
choose external projects from `list_scopes`, and set the handle, primary flag and access. For
`api` strategies the subscription is ensured at the same time. For `manual` ones, the UI shows the
URL, header and token to paste into the tracker (YouTrack's Webhook Triggers app).

### 4.4 Ownership and permissions: the GitHub model

Trackers follow the rules the GitHub integration already uses:

| | GitHub today | Trackers |
|---|---|---|
| Where a connection starts | From a project; there is no company-wide integrations screen (`Web::Company::Integrations::GithubSetupController`) | From a project |
| Who connects, reconnects, disconnects | Project admin or project owner (`IntegrationsPolicy#manage_integrations?`) | Same policy |
| Proof on first connect | Going through GitHub's install flow, plus OAuth installation ownership where configured | Entering working credentials, or completing the provider's OAuth consent |
| What the connection can reach | Decided **on GitHub** by the org admin: all repositories or selected ones | Decided **in the tracker** by its admin: the projects the connection's identity (bot account, OAuth consenting user, approved Azure projects) can see |
| Other projects in the company | Link an installation the company already holds, with no new proof (`Github::IntegrationService#create`, `github_installation_held_by?`) | Link the company's existing connection, with no new credentials |
| Who picks what a project uses | Anyone with write access adds repositories from the installation's list (`RepositoriesPolicy#create?`) | Anyone with write access adds project trackers from the connection's `list_scopes` |
| Removing | A project admin removes that project's row; a company-wide row needs a company admin (`IntegrationsController#destroy`) | A project admin or owner **unlinks** the connection from their project (its trackers are detached). Reconnecting or disconnecting the shared connection itself needs a company admin or the person who connected it. |

There is no Aixle-side allow-list of external projects. The boundary is the tracker's own
permissions, just as GitHub's is the App's repository selection. Operator docs and the connect
screen say so: give the automation account access only to the projects Aixle should see.

One difference is deliberate. GitHub keeps one `Integration` row per project for the same
installation, because its credential is only an installation id and tokens are minted per request.
A tracker credential is a secret (a permanent token, or OAuth tokens). Copying it per project
would mean one rotation per project. So a tracker connection is **one** company-held row
(`project_id` NULL, created from whichever project first connected it), and the per-project unit
is the `ProjectTracker`. The connection's creator can instead keep it project-only (`project_id`
set), and then no other project can link it.

## 5. Provider port

### 5.1 Interface

```ruby
module Trackers
  PROVIDERS = {
    "youtrack" => Trackers::Youtrack::Provider,
    # "jira" => Trackers::Jira::Provider, ...
  }.freeze

  # One instance per Integration; owns that connection's client. Every method
  # returns normalized DTOs (§5.2) and raises Trackers::Error subclasses
  # (NotFound, NotAuthorized, ValidationFailed, RateLimited, OutcomeUnknown).
  class Provider
    def self.for(integration) = PROVIDERS.fetch(integration.provider.to_s).new(integration)

    def capabilities = Set[]           # :labels, :transitions_graph, :native_query, :multi_assignee

    # Connection
    def verify!                        = raise NotImplementedError  # -> Identity
    def list_scopes(query:, cursor:)   = raise NotImplementedError  # -> Page[Scope]
    def describe(scope_id)             = raise NotImplementedError  # -> Metadata (statuses, types, fields)

    # Issues — every method takes the scope and must reject entities outside it
    def get_issue(scope_id, ref)                    = raise NotImplementedError
    def search_issues(scope_id, filter, cursor:)    = raise NotImplementedError
    def create_issue(scope_id, attrs)               = raise NotImplementedError
    def update_issue(scope_id, ref, attrs)          = raise NotImplementedError
    def transition_issue(scope_id, ref, status)     = raise NotImplementedError
    def list_comments(scope_id, ref, cursor:)       = raise NotImplementedError
    def add_comment(scope_id, ref, body)            = raise NotImplementedError
    def list_users(scope_id, query:, cursor:)       = raise NotImplementedError
    def change_recorded?(scope_id, ref, change)     = raise NotImplementedError  # history lookup, §6.2

    # Events
    def subscription_strategy          = raise NotImplementedError  # :manual | :api
    def ensure_subscription!(sub)      = nil                        # :api — register or re-register
    def refresh_subscription!(sub)     = nil                        # :api with expiry (Jira: 30 days)
    def remove_subscription!(sub)      = nil
    def setup_instructions(sub)        = nil                        # :manual — what to paste where
    def authentic?(request, sub)       = raise NotImplementedError
    def parse(raw_body)                = raise NotImplementedError  # -> [Notification]
  end
end
```

The registry is an explicit hash. Five providers do not need `.descendants` discovery, and the
reviewer of PR #271 asked for exactly this.

### 5.2 Normalized DTOs

```text
Notification  kind (:issue_created | :issue_updated | :comment_created), scope_id, issue_id,
              comment_id?, changes [{field, from, to}], actor_id?, delivery_id?, occurred_at
Issue         id, key, url, title, description, type, status {id, name, category},
              assignees [User], reporter, labels [], scope_id, created_at, updated_at,
              fields {field_id => value}      -- only fields that describe() reported
Comment       id, author, body, created_at, url
Status        id, name, category (todo | in_progress | done | canceled | nil)
```

### 5.3 Provider-specific facts the port absorbs

| | YouTrack | Jira Cloud | Linear | GitHub Projects | Azure Boards |
|---|---|---|---|---|---|
| Scope unit | project | project | team | project (v2) | project |
| Instance identity | normalized base URL | `cloudId` (survives site rename) | organization id | owner + project node id | organization id |
| Auth | permanent token of an automation account | Atlassian OAuth 2.0 app, configured per deployment like Azure's Entra app; tokens go through the existing OAuth flow engine (`oauth-implementation.md`). It acts as the consenting user, so consent comes from a dedicated service account | API key or OAuth app | GitHub App (existing) | existing Azure connection |
| Delivery | Webhook Triggers app (YouTrack 2026.2+), configured per project; one shared token header per YouTrack project | REST-registered webhooks (OAuth/Connect apps) expire after 30 days and need the refresh endpoint | webhooks with `Linear-Signature` HMAC-SHA256 and `webhookTimestamp` | `projects_v2_item` through the existing GitHub App receiver | Service Hooks through the existing Azure receiver |
| Subscription strategy | manual | api + refresh sweep | api | GitHub App install | api (existing `SubscriptionService`) |
| Change hints in payload | `changedFields[{name, oldValue, value}]` | `changelog.items` from/to | `updatedFrom` (previous values) | `changes` (to verify) | `fields.{name}.oldValue/newValue` |
| Status category source | `isResolved` only (todo/done); in-progress set by mapping | `statusCategory` | state `type` | none — mapping required | state category |

For GitHub and Azure, `parse` is fed by their existing controllers. Each hands the tracker pipeline
a `Notification` and never routes through `/webhooks/trackers`.

### 5.4 Status and "columns"

"The issue moved to a column" means the value of the field that the tracker's board is built on
changed:

- YouTrack boards are usually built on `State`.
- A Jira column holds one or more statuses.
- Linear boards use workflow states.
- A GitHub project board uses a single-select field, `Status` by default.
- Azure has both `System.State` and `System.BoardColumn`.

Each project tracker stores `settings.status_field`. The provider supplies the default and the
tracker UI can override it. `describe` returns the status values with a category where the
provider has one, and the project tracker can override categories. Triggers can then filter on
either the exact status name (`"In Review"`) or the portable category (`done`).

The name `status_changed` is deliberate: in Aixle, "column trigger" already means a move on the
**Aixle** board (`ColumnWorkflowBinding`).

## 6. Events and triggers

### 6.1 Pipeline

```text
POST /webhooks/trackers/:endpoint_token          (or GitHub/Azure receivers → Notification)
  → TrackerSubscription (active) → provider.authentic?(request, sub)      401 otherwise
  → body limit (512 KB, before params are parsed) → provider.parse → [Notification]
  → cheap drop: no active ProjectTracker for (integration, scope) with an enabled tracker binding
  → TrackerDelivery.create (unique dedup_key)  → 200                     duplicate → 200, no-op
  → Trackers::ProcessDeliveryJob
      provider.get_issue (+ comment)           authoritative state, our credentials
      verify change hints (§6.2)
      derive normalized events; drop events whose actor is the connection identity
        unless a binding opted in (§6.3)
      for each ProjectTracker mapped to (integration, scope):
        TriggerEngine.publish(event_type:, project:, data:, dedup_key:)   -- existing outbox
  → TriggerBinding.for_event + project_tracker_id match + TriggerFilter → fire_workflow
```

Nothing from the request body except IDs and change hints is persisted. Text shown to agents or
written into task bodies comes from the API response and is bounded (§7.5). The data-minimization
branch PR #271 added at ingress is not needed.

### 6.2 Trusting change hints

A payload's change hint (`status: Open → Ready`) is accepted when the re-read issue's current value
equals the hint's `to`. When it differs (the issue already moved on), `change_recorded?` checks the
provider's history (YouTrack activities, Jira changelog, Linear history, Azure updates). An
unconfirmed hint is skipped with an `unconfirmed_change` diagnostic. Fast consecutive moves still
fire every trigger, and a forged hint cannot invent a transition that never happened.

### 6.3 Event vocabulary and data

| Event type | Source | Emitted when |
|---|---|---|
| `tracker.issue.created` | `issue_created` | always |
| `tracker.issue.status_changed` | `issue_updated` with the status field in `changes` | hint confirmed |
| `tracker.issue.assigned` | `issue_updated` with the assignee in `changes` | hint confirmed; one event per added assignee |
| `tracker.comment.created` | `comment_created` | always; `comment.mentions_me` computed from the fetched body |

Event `data`, which trigger filters match against. This is a documented contract, the same for
every provider:

```json
{
  "tracker": { "id": 12, "handle": "youtrack-app", "provider": "youtrack" },
  "issue": {
    "id": "2-1234", "key": "APP-123", "url": "https://…/issue/APP-123",
    "title": "…", "type": "Bug",
    "status": { "name": "Ready for AI", "category": "todo" },
    "assignees": ["aixle-bot"], "labels": ["ai"], "reporter": "jdoe"
  },
  "change": { "field": "status",
              "from": { "name": "Open", "category": "todo" },
              "to":   { "name": "Ready for AI", "category": "todo" } },
  "comment": { "id": "4-55", "author": "jdoe", "mentions_me": true, "text": "…" },
  "actor": { "id": "…", "login": "jdoe", "name": "Jane Doe", "is_me": false },
  "text": "…"
}
```

`text` is the bounded title + description for created issues and the bounded comment body for
comments. Events caused by Aixle also carry `origin` (§6.6). It keeps the Slack-style "text matches" control usable unchanged.

`TriggerFilter` gains one operator, `includes` (array membership). `contains` stringifies its
operand, so `labels contains "ai"` would also match `"main"`.

### 6.4 Trigger binding

- **Kind** `tracker` in `WorkflowTriggers::Creator::KINDS`. `event_type` is one of §6.3, required,
  with no default.
- **`project_tracker_id`** selects one tracker. `null` means any tracker in the project, which is
  what a migration period wants (§8). Validation: the tracker belongs to the binding's project and
  is not detached.
- **Filters** are an ordinary `filter_predicate`. Examples:
  `{"change.to.name": {"op": "in", "value": ["Ready for AI"]}}`,
  `{"change.to.category": "done"}`, `{"issue.type": "Bug"}`,
  `{"issue.labels": {"op": "includes", "value": "ai"}}`, `{"comment.mentions_me": true}`.
- **Changes made by Aixle** are governed by the binding's `aixle_changes` setting, not by a
  filter. §6.6 covers it.
- **Run owner**: the binding's creator, as for webhook triggers today (`TriggerEngine#fire_for_binding`).
  Mapping the tracker actor to an Aixle user comes later, together with the Teams design.
- **Failure notice**: the binding's failure-reporting setting applies to tracker bindings too.
  Today that setting is `notify_on_failure`, which is Slack-only. The Teams design replaces it
  with `status_reporting` (`none | failures | lifecycle`); tracker bindings default to `failures`.
  A failed run posts one short comment with a link to the run on the issue that started it. The
  comment is an attributed Aixle write (§6.6).
- **Actor shape**: `actor` matches the Teams design's `{id, name, aixle_user_id}`, plus `login` and
  `is_me`. `aixle_user_id` stays empty until actor-to-user mapping exists.
- **Subject policies**: the existing three, plus `find_or_create_task`, the default for tracker
  triggers:
  - `existing_task` — the active board task in this project linked to the issue. Prefer a link
    created by the same workflow, then the oldest link. With several cross-workflow candidates,
    none is chosen and an `ambiguous_external_subject` diagnostic is recorded (PR #271's rule).
  - `create_task` — always a new task plus a link.
  - `find_or_create_task` — the `existing_task` result, otherwise `create_task`. It runs under an
    advisory lock on (project, provider, instance, issue id), because `issue.created` and
    `status_changed` for the same issue can dispatch concurrently under different
    `TriggerDispatch` locks.

### 6.5 Dedup

- **Delivery** (before acknowledging): the provider's delivery ID when it has one. Otherwise
  `SHA-256(subscription, kind, issue_id, comment_id | changed-field signature | updated_at)`.
- **Event** (`TriggerEvent.dedup_key`): `SHA-256(project_id, provider, instance, issue_id,
  event_type, discriminator)`. It is computed from the external identity, not from the
  subscription, so two connections to the same external project mapped into the same Aixle
  project fire once.
- **Launch**: the existing `TriggerDispatch` key (event + binding).

Delivery stays best-effort in v1. The UI shows `last_event_at` and the subscription status, and
never promises lossless delivery. A cursor-based gap sweep is an additive capability later (§12).

### 6.6 Changes made by Aixle: chaining without loops

An agent writes through the connection's identity, so its own actions come back as tracker events.
Without a rule, this loops:

- A "comment mentions @aixle" trigger starts a run. The agent's reply quotes `@aixle`, and the run
  starts itself again.
- A "status changed" trigger without a status filter starts a run. The agent moves the issue, and
  the same workflow starts again.

Some of those events are wanted: "when the dev workflow moves the issue to In Review, start the
review workflow". The rule therefore tracks **which run caused a change**, not merely **that Aixle
caused it**.

**Attribution.**

1. Every write a `tracker_*` tool makes is recorded in `tracker_operations` **before** the provider
   call (state `pending`, then `succeeded`/`failed`). The row carries the run and workflow that
   made it, the run's chain, and what it changes. A notification can arrive before the API call
   returns, and it still finds the row.
2. When a notification comes back, the job matches it to the ledger:
   - created comments and issues: exact match on the returned id (`result_ref`);
   - status and assignee changes: the same issue, field and `to` value, within a short window of
     the write (10 minutes, to be tuned).
3. A matched event carries its origin:

   ```json
   "origin": { "aixle": true, "attributed": true, "workflow_run_id": 881,
               "workflow_id": 42, "chain": [42, 57], "depth": 2 }
   ```

   `chain` is the list of workflow ids that led here: the origin run's own chain plus its workflow.
   A run started from such an event stores `chain` and `depth` in `shared_context["tracker"]`, and
   its writes pass them on.
4. A change by a connection identity that matches no ledger row (someone used the bot account by
   hand, or another system shares the token) gets `{"aixle": true, "attributed": false, "chain":
   [], "depth": 1}`.
5. A person's change has no origin and starts a fresh chain.

`actor.is_me` (and so `origin.aixle`) is true when the actor is the identity of **any** active
connection of the company to the same instance, not only the one that delivered the event.
Otherwise two connections with different bot users would trigger each other. The identity should be
a dedicated automation account: a token owned by a person makes that person's own edits count as
Aixle's.

**Per-binding setting** — `aixle_changes`:

| Value | Fires on an Aixle-caused event when | For |
|---|---|---|
| `ignore` (default) | never | triggers that react to people |
| `other_workflows` | the binding's workflow is **not** in `origin.chain` | chaining: dev → review. Blocks a workflow starting itself and cycles such as A → B → A. |
| `always` | always, including its own workflow | deliberate state machines that walk an issue through statuses one run at a time |

**Hard limits**, project settings that no binding can switch off:

- **Chain depth**, default 5. An Aixle-caused event at or beyond it fires nothing
  (`chain_depth_limit`).
- **Per-issue budget**, default 10 Aixle-caused runs per issue per rolling hour, across all
  bindings (`issue_chain_budget`).
- Existing cooldown and session admission.

A skip is recorded on its `TriggerDispatch` (`status: skipped`, `detail.reason`), the way cooldown
is recorded today, and shows in the trigger's activity.

Example with `other_workflows` on both bindings:

1. A person moves APP-1 to Ready. Dev workflow W1 starts: chain `[]`.
2. W1 moves APP-1 to In Review. The event carries chain `[W1]`. Review workflow W2 fires, and its
   run has chain `[W1]`.
3. W2 moves APP-1 back to Ready. The event carries chain `[W1, W2]`. W1 is in the chain, so W1 does
   not fire.
4. Once a person touches APP-1 again, the chain starts over.

With `always`, the same cycle runs until the depth or the per-issue budget stops it.

### 6.7 Templates

`Templates::Exporter` writes a tracker binding without its `project_tracker_id`. On install it
becomes "any tracker" of the target project. Filters, `aixle_changes` and the subject policy
travel as they are. Status **names** differ between trackers, so templates meant for sharing
should filter on `change.to.category`. The installer already creates every trigger disabled, so a
person reviews the filters before anything fires.

### 6.8 Board intake: one column

Enterprise boards are owned by other teams, and Aixle has to fit into them without re-modelling
them. The lightest adoption step is **one column**: the customer adds a status such as "Aixle" or
"Ready for AI" to the board, and moving a ticket there starts a workflow.

- **Setup.** "Connect a board column" on the project's Trackers page is a three-step shortcut:
  pick the tracker, pick the column (statuses from `describe`), pick the workflow. It creates an
  ordinary `tracker.issue.status_changed` binding with `change.to.name in [column]`,
  `find_or_create_task` and `aixle_changes: ignore`. Nothing about it is special afterwards; it
  can be edited like any trigger. A marketplace template ("Tracker intake") ships the same thing
  with a starter workflow.
- **When a column is expensive.** In Jira company-managed projects a new status means editing a
  shared workflow, which needs a Jira administrator. Two entry points need no board change and use
  the same shortcut:
  - **assign to the automation account** — `tracker.issue.assigned`, filtered to the bot;
  - **mention it in a comment** — `tracker.comment.created` with `comment.mentions_me`.

  Azure boards can add a column without a new state, which the `System.BoardColumn` status field
  covers (§5.4).
- **Handoff statuses** (§6.9) make the intake column behave like a queue.

### 6.9 Handoff statuses (proposed, open decision 17)

On its own, an intake column fills up, and the board shows nothing about what Aixle is doing.
Handoff statuses are optional binding settings. Each is **one transition at one moment of the
run**, not mirroring:

```text
Ready for AI ──(run accepted)──▶ In Progress ──(run completed)──▶ Review
                                     └──────(run failed / cancelled)──▶ To Do  + failure comment
```

**Settings.** A binding column `tracker_handoff jsonb`:

```json
{ "start":   { "id": "…", "name": "In Progress" },
  "success": { "id": "…", "name": "Review" },
  "failure": { "id": "…", "name": "To Do" } }
```

- Every key is optional. Statuses are picked from `describe` and stored by id **and** name:
  the id survives a rename, and the name is the fallback when the id is gone.
- On an "any tracker" binding, only names are stored, and each is resolved per tracker at run
  time.

**Moments.**

| Hook | When | Why then |
|---|---|---|
| `start` | The run is created by the dispatch, after commit. | The ticket leaves the intake column **immediately**, so nobody picks it up twice. Time spent waiting in the admission queue is visible in Aixle, not on the tracker. |
| `success` | The run transitions to `completed`. | |
| `failure` | The run transitions to `failed` **or `cancelled`**. | A cancelled run did not do its job either. Leaving the ticket in "In Progress" forever is the worse outcome. The comment says "cancelled by …" instead of the failure reason. |

The hooks use the run-transition seam shared with the Teams design
(`docs/design/teams-integration.md` §17, on its own branch):

- `WorkflowRunStateMachine#announce_transition` replaces `announce_failure` and fires on
  start/complete/fail/cancel. It stays on the state machine for the reason `announce_failure`
  gives: the stale-run sweeper calls `fail!` directly.
- `TriggerEngine` fires it for `dispatched` and `skipped` too.
- It enqueues `Triggers::ReportRunTransitionJob(dispatch_id, transition)`, which calls every
  registered origin reporter. `Chat::RunStatusReporter` is one of them; `Trackers::HandoffReporter`
  is ours.

The mapping is `dispatched` → `start`, `completed` → `success`, and `failed` or `cancelled` →
`failure`; `started` and `skipped` are ignored. Each reporter runs as its own job, with its own
idempotency key `(dispatch, transition, reporter)` and its own retries. A tracker transition
retrying for an hour must never re-post a chat message. The reporter re-reads the run, so a job
that runs before the transition's transaction commits sees the old state and retries. (Today
Solid Queue shares the primary database, so an enqueue from the transition commits with it. The
contract holds even if the queue database is split later.)

**Rules that keep it safe.**

0. **Monotonic.** Reporter jobs can run out of order, so the job treats its transition as a
   wake-up and acts on the run's current state:
   - `start` is a no-op once the run is terminal, or once a `success` or `failure` handoff is
     recorded for the dispatch;
   - `success` and `failure` are mutually exclusive, because a run ends once;
   - `start` also runs the compare-and-set below: it moves the ticket only if it is still in the
     status that triggered the run.
1. **Compare-and-set, never force.** Before `success` or `failure`, the job re-reads the issue and
   moves it only if its status is still the one the handoff expects:
   - the `start` status, when the ledger shows that the start write succeeded;
   - otherwise the status that triggered the run.

   If a person or the agent moved the ticket in the meantime (to "Blocked", or to "Review" through
   `tracker_transition_issue`), the handoff is skipped with `status_moved_elsewhere`. A workflow
   that manages statuses itself therefore never fights its own handoff.
2. **Snapshot at dispatch.** The handoff config is copied into the run's `shared_context["tracker"]`
   (with `binding_id`). Editing the trigger never changes what an in-flight run does.
3. **One active run per issue and binding.** A binding with handoff statuses skips an event while a
   run it started for the same issue is still active (`already_running_for_issue`). Two runs that
   both set "In Progress" would otherwise make the compare-and-set unable to tell them apart.
4. **Attributed writes.** Handoff transitions and the failure comment go through
   `tracker_operations` with the run's chain (§6.6), like any Aixle write.
   - `aixle_changes: ignore` (the default) keeps them from triggering anything.
   - With `other_workflows` on the **next** binding, a handoff becomes declarative chaining: dev
     completes, the handoff moves the ticket to "Review", and the review workflow's trigger on
     "Review" fires. Loop protection is unchanged.
5. **Validation at save.**
   - `start` differs from the intake status.
   - A `read_only` tracker cannot have handoff statuses.
   - With `aixle_changes: always`, no handoff status may equal the binding's own trigger status.
     That is an immediate self-retrigger, and the limits would be the only thing stopping it.
6. **Transitions the tracker refuses.** Jira workflows restrict which moves are allowed, and a
   transition can require screen fields. At run time `transition_issue` looks for a transition from
   the current status to the target. If none is allowed, or the tracker rejects it, the handoff is
   skipped with `transition_not_allowed` and the tracker's message. It never takes a path through
   intermediate statuses.
7. **Delivery.** The reporter job is idempotent, keyed by `(dispatch, transition)` in the ledger. It retries transient
   provider errors with backoff for about an hour, then gives up with `handoff_failed`. A handoff
   failure never changes the run's own outcome.
8. **Order on failure.** The comment is posted first and the transition second, so the ticket
   arrives back in "To Do" with its explanation already on it.

**Visibility.** Each hook's outcome is shown on the run page and in the trigger's activity: moved,
skipped (with the reason) or failed.

**Not included.** A `waiting` hook for runs that stop at an approval gate ("Waiting for approval in
Aixle") is the natural next one. It is left out until gates report a run-level state. Reassigning
the ticket, and custom comments per hook, are also left out.

## 7. Agent tools

### 7.1 Tool set

| Tool | Access | Notes |
|---|---|---|
| `tracker_list` | read | The project's trackers: handle, provider, external project, primary, access, status. The discovery tool, like `azure_devops_list_connections`. |
| `tracker_describe` | read | Statuses with categories, issue types, fields. |
| `tracker_search_issues` | read | Structured filter (`text`, `status`, `category`, `type`, `assignee`, `labels`, `updated_since`) plus an optional `native_query` (JQL, YouTrack query) where the provider supports it. Paginated. |
| `tracker_get_issue` | read | By id, key or URL. |
| `tracker_list_comments` | read | Paginated. |
| `tracker_list_users` | read | Exact IDs/logins for assignment and mentions. |
| `tracker_create_issue` | write | Title, description, type, labels, fields. Inside a task-scoped run, links the new issue to the run's board task. |
| `tracker_update_issue` | write | Title, description, fields, labels add/remove. Any field the provider reports as editable, except those on the tracker's deny list. |
| `tracker_transition_issue` | write | Target status by name or id; validated against allowed transitions where the provider has a workflow graph (Jira). |
| `tracker_assign_issue` | write | Set or add assignees. |
| `tracker_add_comment` | write | Comment body. |
| `tracker_link_task` | write (Aixle) | Link a board task to an issue. For manually created issues and for migrations (§8.3). |

Results are compact JSON with stable IDs and URLs and `{has_more, next_cursor}` for lists
(default 50, max 100), following Azure §8.3. Cursors are bound to the tracker and the filter.

### 7.2 Target resolution

Every tool takes an optional `tracker` (handle or id). The target is resolved in this order:

1. **Explicit** `tracker` — must be a project tracker of the session's project and not detached.
2. **Run affinity** — `shared_context["tracker"]["project_tracker_id"]` of a tracker-started run.
   If that tracker is detached or its connection is disconnected, the call **fails closed** with a
   message saying so. It never falls back to another tracker.
3. **Issue reference** — a URL whose instance, or a key whose prefix, matches exactly one project
   tracker.
4. **Primary** — the project's primary tracker, or its only tracker.
5. Otherwise an error listing the handles and pointing at `tracker_list`.

Then:

- **Writes** to a `read_only` tracker are refused with a message naming the primary tracker.
- **Every entity** the provider returns is re-checked against the tracker's external scope before
  it is returned or mutated. That includes `native_query` results, because a query string appended
  after a scope predicate can escape it.
- **Credentials** are decrypted in Rails for the resolved connection only. They never enter agent
  context, arguments, output or the container environment.

### 7.3 Availability and injection

- **Availability.** The tools are tagged `tracker` and declare an `availability` predicate: the
  project has at least one active project tracker. With one, they appear in the tool picker under
  "Trackers" and can be attached to a workflow or step like any other tool (capability 2).
- **Injection.** A new injection rule, `tracker_run`, matches when the session's workflow run has
  `shared_context["tracker"]`. The tools declare `inject_when :tracker_run`, so a tracker-started
  run has them without anyone attaching them (capability 3).
- The tools are **not** injected into every session of a project that merely has a tracker (Azure
  and Coder do that). Twelve tools would sit in every prompt otherwise (decision 2).

### 7.4 Idempotency

Every tracker write goes through `tracker_operations`, which also records causality (§6.6). For
`tracker_create_issue` and `tracker_add_comment` the row is also an idempotency guard. The operation
key is the caller's optional `operation_key`, or else is derived from `(session, tool,
request_digest)`, so an agent's retry of an identical call does not file a second ticket. A timeout
after dispatch is reported as `outcome_unknown` with a read-back hint, not blindly retried. The
semantics are Azure's, §8.3.

### 7.5 Run context

A tracker-started run gets:

```json
"tracker": { "project_tracker_id": 12, "handle": "youtrack-app", "provider": "youtrack",
             "event_type": "tracker.issue.status_changed",
             "issue": { "id": "2-1234", "key": "APP-123", "url": "…", "title": "…",
                        "status": "Ready for AI" },
             "change": { "field": "status", "from": "Open", "to": "Ready for AI" },
             "comment": { "id": "4-55", "text": "…" },
             "chain": [42], "depth": 1 }
```

A `ContextBuilders::TrackerContext` section (`applicable?` when the key is present) tells the
agent which tracker and issue started the run, that tools default to that tracker, and that full
data is live via `tracker_get_issue`. Title, description and comment text are bounded to 500
characters, the same limit as `ContextBuilders::BoardContext`.

## 8. Several trackers in one project

### 8.1 Model

- A project may have any number of project trackers.
- At most one is **primary**. It is where untargeted reads and creates go (§7.2 step 4).
- Each is **read_write** or **read_only**. A read-only tracker still emits events and serves reads.
- Handles are what agents and triggers see. Workflows that pass `tracker: "legacy-jira"` keep
  working when the connection behind the handle is rotated.

### 8.2 Parallel use

Example: bugs live in YouTrack and product work in Jira.

- Triggers name their tracker.
- Runs started by a tracker event are pinned to that tracker.
- Untargeted tool calls outside a tracker run go to the primary tracker. When that is not what the
  agent wants, keys (`APP-12` vs `PROJ-7`) and URLs disambiguate without the `tracker` argument.

### 8.3 Migration (Jira → YouTrack)

1. **Add** the YouTrack tracker (`read_write`, not primary). Switch the triggers that should
   survive the move to "any tracker", or duplicate them for YouTrack. Workflows need no edit,
   because they use `tracker_*` tools and `tracker.*` events.
2. **Pause** tracker triggers during the bulk import. An import creates thousands of issues, and
   each one is a `tracker.issue.created`. Admission caps bound the damage, but they do not avoid
   it.
3. **Flip primary** to YouTrack. New issues filed by agents go there.
4. **Set Jira `read_only`.** Agents can still read old tickets and cannot write to them.
5. **Relink** where it matters. A board task can hold links to the Jira issue and the imported
   YouTrack issue. `tracker_link_task` (or a one-off script using the importer's key mapping) adds
   the second link. Identity mapping between trackers is not automatic.
6. **Detach** Jira. Its triggers are disabled, its links stay visible read-only on the tasks, and
   its connection can be disconnected.

## 9. Platform integrations: Azure DevOps and GitHub

### 9.1 A tracker is a capability, not a kind of connection

An `Integration` is a connection to a **vendor**, not to a feature. YouTrack, Jira and Linear
provide one capability: a tracker. Azure DevOps and GitHub are platforms, and one connection serves
several capabilities:

| Capability | Azure DevOps | GitHub |
|---|---|---|
| Code hosting (repositories, clone/push credentials) | yes — `AzureDevops::RepositoryService`, `SessionGitSetup`, derived-key Git credentials | yes — GitHub App installation tokens, `refresh_github_token` |
| Pull requests and CI gates | yes — `azure_devops_*pull_request*`, builds, `ResolveAzureDevopsEventJob` | yes — `Webhooks::GithubController` |
| Boards / issues | yes — `AzureDevops::WorkItemService`, `azure_devops_*work_item*` tools | Issues and Projects — not built |

Azure is built differently from this design because most of it is **not** a tracker. Its
repository, pull-request and CI parts solve code-hosting problems that YouTrack or Jira never have,
and they stay exactly as they are.

Only the boards part converges. A platform implements the tracker port **over its existing
connection, client and event receiver**:

- no second connection;
- no second credential store;
- no second webhook subscription table.

A `ProjectTracker` for Azure Boards points at the existing Azure `Integration`, and its
`external_scope_id` is one of that connection's `azure_project_ids`.

A shared "code host" port across GitHub, GitLab and Azure (repositories, PRs, CI) would follow the
same capability idea. It is a separate decision and is not needed for trackers.

### 9.2 Azure Boards as a tracker provider

`Trackers::AzureDevops::Provider` is a thin adapter. Almost every port method already exists on
`AzureDevops::WorkItemService`, including the capability-profile checks (`client_for(:"work_items.read")`),
revision guards and the project-scope re-check:

| Port method | Azure implementation |
|---|---|
| `verify!` | existing connection verification |
| `list_scopes` | `Integration#azure_project_ids` / `azure_project_names` |
| `describe` | `work_item_types` — already returns each type's states **with their category** |
| `get_issue` / `search_issues` | `get` / `query` — structured filters only; no `native_query`, because the Azure design forbids caller-supplied WIQL |
| `create_issue` / `update_issue` | `create(type:, fields:)` / `update(fields:, expected_revision:)` |
| `transition_issue` | `update` of `System.State` (or `System.BoardColumn` when that is the tracker's status field) |
| `list_comments` / `add_comment` | `comments` / `add_comment` |
| `list_users` | new — Azure identity search; may ship as unsupported in the first cut |
| `change_recorded?` | work-item updates API — new |

- **Events.** `workitem.created`, `workitem.updated` and `workitem.commented` are added to
  `AzureDevopsSubscription::EVENT_TYPES` and created by the existing `SubscriptionService`. The
  existing `Webhooks::AzureDevopsController` authenticates, and `AzureDevopsDelivery` deduplicates
  before acknowledging, as today. `ResolveAzureDevopsEventJob` gets one more branch: it builds a
  `Trackers::Notification` from a `workitem.*` delivery and hands it to the tracker pipeline.
  `tracker_subscriptions` and `/webhooks/trackers` are not used for Azure.
- **Ledger.** Work-item writes go through `tracker_operations` like every other provider's, so
  they get the same causality tracking (§6.6). `azure_devops_operations` stays for pull-request
  operations.
- **Target resolution.** The Azure design refuses any default when more than one project is
  possible, because "the first connection" depends on row order. §7.2 keeps that rule: its only
  default is the **primary** tracker, which a person chose explicitly, and after that an error.
  Row order never decides.
- **Tool overlap: removed at once.** Two names for one operation are not kept side by side, and
  there is no deprecation release. The change that ships the Azure Boards provider also:
  1. **Deletes** `azure_devops_create_work_item`, `get_work_item`, `update_work_item`,
     `query_work_items`, `list_work_item_comments`, `add_work_item_comment` and
     `list_work_item_types`.
  2. **Creates project trackers** for existing connections, with a data migration: one per
     (Aixle project that sees the Azure connection × Azure project it covers). The handle is
     derived from the Azure project name. When a project ends up with exactly one tracker, it is
     primary.
  3. **Re-points explicit attachments** of the deleted tools to their `tracker_*` equivalents in
     the same migration. Code-first tools need a migration only for a rename or removal.
  4. **Reports step instructions** that name a deleted tool (a list of workflow and step ids). The
     argument shapes differ (`integration_id` + `azure_project_id` versus `tracker`), so text is not
     rewritten automatically.

  `azure_devops_link_work_item` links a **pull request** to a work item, so it is a code-host
  operation and stays. `azure_devops_list_connections` also stays: the build and PR tools still
  need it.

### 9.3 GitHub Issues and Projects

Same shape:

- the GitHub App installation is the connection;
- `Trackers::Github::Provider` wraps the existing GitHub client;
- `issues` and `projects_v2_item` events reach the tracker pipeline as `Notification`s from the
  existing `Webhooks::GithubController`.

GitHub Issues belong to a repository and Projects to an owner, so the scope unit is decided when
this provider is designed (phase 3). Repository and PR behaviour is untouched.

## 10. Security

- **Authentication per provider**: HMAC where the provider signs (Linear, Jira), basic auth per
  subscription (Azure), a shared header token where that is all the provider offers (YouTrack).
  The YouTrack token is shared by every consumer of that YouTrack project, so it is weak. Re-reading
  through the API (§6.1) is what makes a forged notification harmless: the most it can do is make
  us read a real issue that is really in the claimed state.
- **Transport**:
  - Azure, Jira Cloud, GitHub and Linear call fixed vendor hosts through their clients.
  - A customer-chosen base URL (YouTrack, possibly self-hosted) goes through the PR #271 transport:
    `UrlSafetyValidator` on save and on every request, the validated IP pinned, redirects not
    followed, bounded response size, TLS verification that cannot be disabled.
  - Every client bounds response size and time.
- **Scope**: every returned entity is re-checked against the tracker's external project (§7.2).
  `read_only` is enforced in Rails, not in prompts.
- **Loops**: causality tracking with the per-binding `aixle_changes` setting and hard depth and per-issue limits (§6.6), cooldown, and session admission.
- **Logs** carry IDs, event kind and disposition only. Tokens, headers, bodies and issue text are
  never logged.

## 11. UI

- **Project → Trackers**: a list of project trackers with provider, external project, primary,
  access, status, subscription health (`last_event_at`), and manual setup instructions (copy URL
  and token). "Add tracker" picks an existing visible connection or creates one. The credentials
  form is the only per-provider UI, rendered from provider-declared connection fields.
- **Project → Integrations**: the connections this project uses, with Test connection and Unlink,
  plus Reconnect and Disconnect for those allowed (§4.4). This follows GitHub; there is no
  company-wide integrations screen.
- **Trigger form**: kind "Tracker":
  - tracker picker, or "Any tracker";
  - event;
  - filters built from `describe` metadata: status from/to, category, type, labels, "only when
    Aixle is mentioned", text match;
  - subject policy;
  - "Changes made by Aixle": ignore / only from other workflows / always.

  The form is the same for every provider.
- **Task details**: linked issues (provider, key, link), read-only. This matches PR #271's
  Task Details block.

## 12. Phasing

Each phase ships on its own. Every new provider tests the port against a shape it was not written
for.

1. **Core + Azure Boards.**
   - **Core:** `project_trackers`, `external_resources`, `tracker_operations` and the binding
     columns; `Trackers::Provider` and the DTOs; the pipeline from `Notification` onward (hydrate,
     verify hints, derive events, fan out, publish); the four events; the trigger kind and form;
     the one-column intake shortcut; the twelve tools with resolution, injection and the causality
     ledger; `aixle_changes` and the limits; `TrackerContext`; `notify_on_failure` comments;
     template export and install; Task Details links.
   - **Azure (§9.2):** the provider over `AzureDevops::WorkItemService`; `workitem.*` Service Hook
     types fed by the existing receiver; in the same change, the duplicate work-item tools are
     deleted along with the project-tracker and attachment migration.
   - **Not needed yet:** `tracker_subscriptions`, `tracker_deliveries`, `/webhooks/trackers` and
     `Trackers::ConnectionService`, because Azure keeps its own connection, subscriptions and
     receiver.
   - **Risk:** this phase changes the tools existing Azure customers have. It needs a live-tenant
     run on staging before release; CI alone cannot show it works.
2. **Jira Cloud** (committed):
   - the tracker-native ingress: subscriptions, deliveries, `/webhooks/trackers`;
   - `Trackers::ConnectionService` (connect, reconnect in place, verify, soft disconnect);
   - the Atlassian OAuth 2.0 app through the OAuth flow engine;
   - the `api` strategy with the 30-day refresh sweep;
   - `cloudId` instance identity, the transition graph, and `native_query` (JQL).
3. **GitHub Projects** (committed), and GitHub Issues if they fall out cheaply: through the
   existing GitHub App and `Webhooks::GithubController` (§9.3). The scope unit is decided here.
4. **Linear**: API-registered webhooks with `Linear-Signature` HMAC. Until then, the dead `linear`
   enum value and the user-guide claim that Linear is supported are corrected.
5. **YouTrack**, last:
   - the `manual` subscription strategy and shared-token authentication (the weakest one);
   - the SSRF-hardened transport copied from PR #271. YouTrack is the only provider on this list
     with customer-chosen, possibly self-hosted base URLs; the others call fixed vendor hosts.
   - PR #271's fate is decided when this phase starts.

Later and additive:

- **Gap sweep** — a per-tracker `search_issues(updated_since: cursor)` that replays missed
  notifications through the same job.
- **Board ↔ tracker status mirroring** — an Aixle column mapped to a tracker status, driven by
  the existing links.
- **Provider-specific tools** — only where the common set cannot express an operation, resolved
  through §7.2.

## 13. Decisions

### 13.1 Agreed

| # | Question | Status |
|---|---|---|
| 1 | Common `tracker_*` tools and `tracker.*` events, or provider-named ones? | **Agreed: common.** Tool names and event types are persisted into workflows and templates, so renaming later is a data migration. Provider power goes through `native_query` and `fields`. |
| 2 | Inject tracker tools into every session of a project with a tracker, or only tracker-started runs plus explicit attachment? | **Agreed: only tracker-started runs plus explicit attachment.** |
| 3 | Make `find_or_create_task` the default subject policy for tracker triggers? | **Agreed: yes.** |
| 4 | Events caused by Aixle? | **Agreed: a per-binding setting.** `aixle_changes` = `ignore` (default) / `other_workflows` / `always`, with causality tracking and hard depth and per-issue limits (§6.6). |
| 5 | Disconnect soft (inactive, credentials wiped, reconnectable) instead of destroy? | **Agreed: yes.** |
| 6 | PR #271: close and salvage, or merge and migrate? | **Agreed: stays open for now.** This design is built on its own branch; PR #271's client and connect verification are copied in the YouTrack phase. |
| 7 | Azure Boards: second set of work-item tools, or one tracker set? | **Agreed: one set, and the duplicates are deleted in the same change** that ships the Azure Boards provider, with no deprecation release (§9.2). |
| 8 | Who may map an external project through a company connection? | **Agreed: the GitHub model** (§4.4). The tracker's own permissions for the connection's identity are the boundary, with no Aixle allow-list. Project admins and owners connect; anyone with write access adds project trackers. |
| 9 | Whose run is a tracker-started run? | **Agreed: the trigger's creator**, as for webhooks. Actor-to-user mapping comes later. |
| 10 | Which fields may agents write? | **Agreed:** everything the provider reports as editable, minus an optional per-tracker deny list. |
| 11 | Failure notice on the issue? | **Agreed:** `notify_on_failure` posts one comment with a link to the run (§6.4). |
| 12 | Phase order? | **Agreed:** Azure Boards (with the core) → Jira → GitHub Projects → Linear → YouTrack. Jira and GitHub Projects are committed (§12). |
| 13 | Jira authentication? | **Agreed: an Atlassian OAuth 2.0 app**, with consent from a dedicated service account (§5.3). |
| 14 | YouTrack older than 2026.2? | **Agreed:** not supported in v1; documented as a requirement. |
| 15 | Loop-limit defaults? | **Agreed:** depth 5, 10 Aixle-caused runs per issue per hour, tuned later. |
| 16 | Scope cuts (no mirroring, no polling, best-effort delivery)? | **Agreed.** Adoption goes through one-column intake instead (§6.8). |

### 13.2 Open

| # | Question | Recommendation |
|---|---|---|
| 17 | Handoff statuses (§6.9)? | Yes, optional, with these sub-decisions: **17a** `start` fires when the run is accepted, not when the first agent starts; **17b** `cancelled` is handled as `failure`; **17c** one active run per issue and binding when handoff is set; **17d** compare-and-set: skip when someone moved the ticket, never force. |
