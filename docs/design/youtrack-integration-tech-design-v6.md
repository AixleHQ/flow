# YouTrack integration — technical design v6

Status: **Phase 1 proposal; explicit approval from Alex is required before Phase 2**
Task: #1738
Date: 2026-09-15

## 1. Purpose and boundaries

V1 delivers four capabilities: connect YouTrack through the existing integration model; configure a YouTrack workflow trigger; start a workflow when a matching event arrives; and give that run first-party YouTrack tools through Aixle's internal MCP server.

The connection selects exactly one YouTrack project (shape A), but may be owned by an Aixle company or project. It stores credentials, endpoint configuration and cached identity/project metadata only. It does **not** import or mirror issues or synchronize YouTrack fields. It does persist one narrow relationship: a generic typed external-resource link from an Aixle task to the stable database ID of the YouTrack issue that caused its creation. This is identity/routing metadata, not a snapshot of YouTrack content; §9 defines the boundary and lifecycle.

The platform does not implement a conversational bot or automatic YouTrack write-back. It does not post progress/failure comments, correlate later replies with an active run, or interpret stop/pause/resume. What an agent does with its tools is determined by workflow instructions.

## 2. Decisions

| Area | V1 decision |
|---|---|
| Scope | Shape A: one integration selects exactly one YouTrack project. Ship both company-owned and project-owned Aixle integrations. |
| Authentication | Customer-supplied permanent token; its owner is the effective identity. No OAuth or refresh flow. |
| Event source | YouTrack Cloud/Server 2026.2+ Webhook Triggers app, manually configured once through **All Events**. No polling or automatic app-setting changes. |
| Events | Exactly `youtrack.issue.created` and `youtrack.comment.mentioned`. |
| Routing | Random endpoint → integration → every enabled binding with that `integration_id`; payload project ID is a consistency check only. |
| Webhook secret | Stored once as `WebhookEndpoint.encrypted_secret`; the integration stores only the header name and endpoint ID. |
| Reliability | Best-effort. No documented webhook retry/order/event-ID contract; no reconciliation. |
| Trigger UI | Reuse generic trigger fields and Slack text-match/Subject controls; add `integration_id`. |
| MCP | One global first-party `youtrack_*` tool set, gated by `requires_integration :youtrack`; calls resolve the triggering integration from run context, then fall back to the active project-level or company-level integration. |
| State | Redacted/matched event/outbox state, immutable run context, and generic task external-resource links. No YouTrack content snapshot or sync state. |

## 3. Verified YouTrack capabilities

| Capability | Verified result and consequence |
|---|---|
| Webhook app and scope | The official app is installed globally and attached/configured per YouTrack project; configuration requires Update Project. It supports multiple callback URLs and an All Events field. This supports shape A and several Aixle destinations per YouTrack project. [Webhook Triggers: installation/configuration](https://www.jetbrains.com/help/youtrack/cloud/webhook-triggers.html) |
| App version/schema | The referenced stock app is 1.0.5 and declares `minYouTrackVersion: 2026.2.0`. Its settings contain a single secret `webhookToken` (minimum 32 characters), one `headerName`, event URL fields, and `webhooksOnAllEvents`. The token is customer-entered and shared by all URLs for that YouTrack project. [JetBrains app source](https://github.com/JetBrains/youtrack-apps/tree/main/packages/webhook-triggers-app) |
| Event payloads | `issueCreated` carries the event/timestamp and an issue object including database/readable IDs, summary, description, reporter and project; `commentAdded` carries the issue/project and comment text/author. These fields are sufficient for matching and initial context. [Supported events and payload structure](https://www.jetbrains.com/help/youtrack/cloud/webhook-triggers.html#webhook-payload-structure) |
| Delivery | The app POSTs JSON, but JetBrains does not document retries, ordering, or a stable event ID. V1 is best-effort and derives a deduplication key. [Webhook delivery/troubleshooting](https://www.jetbrains.com/help/youtrack/cloud/webhook-triggers.html) |
| Permanent tokens | A permanent token executes with its owner's permissions and has no expiration date; it stops working after deletion, user ban, or loss of required permissions. There is no refresh flow. [Manage permanent tokens](https://www.jetbrains.com/help/youtrack/cloud/manage-permanent-token.html), [REST authentication](https://www.jetbrains.com/help/youtrack/devportal/authentication-with-permanent-token.html) |
| REST operations | Issues, comments, custom fields, tags and project users are available through the REST resources; requested response fields must be selected explicitly and updates use POST. [Issues resource](https://www.jetbrains.com/help/youtrack/devportal/resource-api-issues.html), [Projects resource](https://www.jetbrains.com/help/youtrack/devportal/resource-api-admin-projects.html) |
| Native MCP | YouTrack 2025.3+ predefined tools include writes, but they cannot enforce Aixle's selected-project invariant. Custom MCP tools require an app, Low-level Admin and explicit URL inclusion. V1 therefore wraps REST in Aixle-owned tools. [Predefined tools](https://www.jetbrains.com/help/youtrack/devportal/predefined-ai-tools.html), [custom tools](https://www.jetbrains.com/help/youtrack/devportal/custom-ai-tools.html) |

There is no unverified external capability on the critical path. Self-hosted YouTrack must be able to reach Aixle's public HTTPS callback.

## 4. Connection, scope, identity, and health

### 4.1 Existing integration model and ownership

Add `youtrack` to `Integration.provider`; do not create a parallel connection model. `Integration` already belongs to a company, optionally belongs to a project, exposes `company_wide`, `for_project`, and `visible_for_project`, and validates that a selected project belongs to the company ([`app/models/integration.rb`](../../app/models/integration.rb)). This is the same ownership shape used by company-wide Slack and project-first Coder/GitHub.

Both scopes are inexpensive and therefore ship:

- a project integration is visible only to that project;
- a company integration is visible to every project in the company;
- each integration still selects exactly one YouTrack project;
- a company administrator may create/update/disconnect company-wide connections; existing project integration policy (admin or project owner with write access) governs project connections ([`app/policies/web/company/projects/integrations_policy.rb`](../../app/policies/web/company/projects/integrations_policy.rb));
- a workflow editor may select only an active integration returned by `Integration.visible_for_project(binding.project)`.

The only material new work versus project-only scope is endpoint-to-binding routing by `integration_id` and company-level management UI/policy. It needs no content tables, project fan-out table, or duplicate callback.

### 4.2 Connect fields and validation

| Field | Rule |
|---|---|
| Aixle scope | Company or current project. |
| Name | Required display name. |
| Base URL | HTTPS YouTrack URL, normalized exactly like Coder with `url.to_s.strip.chomp("/")`; a self-hosted path such as `/youtrack` is retained. |
| Permanent token | Required; encrypted and masked after save. |
| YouTrack project | Exactly one project readable by the token; persist immutable database ID and display/short names. |
| Webhook header | Required; default `X-YouTrack-Token`. |
| Existing webhook token | Required, at least 32 characters; saved only on the endpoint. Existing values must be accepted because the YouTrack project has one token shared by all consumers. |

At save, call `/api/users/me` and read the selected project. Do **not** probe write permissions: comments, field changes and tag changes cannot be tested without mutation. Successful reads make the record `active`; failure saves it as `error` with a sanitized message, following GitHub/Coder/Slack connect services ([`app/services/github/integration_service.rb`](../../app/services/github/integration_service.rb), [`app/services/coder/integration_service.rb`](../../app/services/coder/integration_service.rb), [`app/services/slack/integration_service.rb`](../../app/services/slack/integration_service.rb)).

Customer documentation and connect-screen copy state the minimum role: read the selected project, issues, fields, comments and project users; create comments; update issues/custom fields including State and Assignee; and manage tags. It does not require Update Comment, attachments, issue links, issue creation/deletion, or Low-level Admin. The person configuring the stock webhook app separately needs Update Project.

### 4.3 Identity

Permanent tokens provide no run-as/impersonation. Resolve and cache `bot_user_id`/`bot_login` from `/api/users/me` and display “connected as @login.” Recommend, but do not require, a dedicated automation account; disclose possible license-seat and notification effects.

### 4.4 Concrete SSRF and egress policy

The YouTrack client must use Aixle's shared `UrlSafetyValidator`, including `BLOCKED_HOSTS`, literal/resolved private/loopback/link-local rejection, and the deployment allow-list `Settings.url_safety.trusted_hosts` ([`app/models/concerns/url_safety_validator.rb`](../../app/models/concerns/url_safety_validator.rb)). This is already used when connecting Coder ([`app/services/coder/integration_service.rb`](../../app/services/coder/integration_service.rb)).

Before storage, normalize the instance base URL exactly as `Coder::IntegrationService#normalize_url` does: `url.to_s.strip.chomp("/")`. Integration settings and `ExternalResource.external_instance` use exactly this value. This intentionally retains a self-hosted path such as `/youtrack`; V1 adds no YouTrack-specific canonicalization rules.

Validation occurs on save **and on every outbound request**. The HTTP transport follows the hardened pattern in `Mcp::OauthDiscoveryService#safe_fetch`: validate each destination, resolve before connect, pin the validated public IP to prevent DNS rebinding, do not let Net::HTTP auto-follow redirects, cap redirects, and validate/pin every redirect hop ([`app/services/mcp/oauth_discovery_service.rb`](../../app/services/mcp/oauth_discovery_service.rb)). HTTPS verification cannot be disabled. A trusted-host exception bypasses private-address rejection intentionally but not scheme/TLS, response-size, timeout, or redirect-hop controls.

### 4.5 Persisted connection and health

```text
Integration.credentials (encrypted): permanent_token
Integration.settings: base_url, youtrack_project_id, project_name,
  project_short_name, bot_user_id, bot_login, webhook_header,
  last_verified_at, last_received_at, error
WebhookEndpoint.encrypted_secret: webhook_token
WebhookEndpoint.config: integration_id
```

There is one logical and physical webhook-secret copy: `WebhookEndpoint.encrypted_secret`. Rotation updates that row. `Integration.credentials` never duplicates it.

There is no periodic provider-health job. Existing GitHub, Coder, GitLab, and Slack integrations set `error` while their connect/setup service fails; only Azure currently exposes a provider-specific “Test connection” action ([`app/services/github/integration_service.rb`](../../app/services/github/integration_service.rb), [`app/services/coder/integration_service.rb`](../../app/services/coder/integration_service.rb), [`app/services/gitlab/integration_service.rb`](../../app/services/gitlab/integration_service.rb), [`app/services/slack/integration_service.rb`](../../app/services/slack/integration_service.rb), [`app/controllers/web/company/projects/integrations_controller.rb`](../../app/controllers/web/company/projects/integrations_controller.rb)). Their runtime clients do not mutate `Integration.status` on ordinary 401/403 responses. YouTrack follows that behavior: a runtime 401/403 returns a sanitized authentication/permission error to the tool caller but does not change connection status. Reconnection repeats the read checks and can update status. `last_received_at` is diagnostic only.

Disconnect disables the endpoint and bindings atomically before deleting credentials. Already accepted events remain auditable; dispatch must re-check active integration before starting, and in-flight calls fail closed after disconnect.

## 5. Callback architecture and shape A

### 5.1 Why `WebhookEndpoint`

`WebhookEndpoint` is the generic inbound callback registry, not merely storage for user-created `kind: webhook` triggers: its model describes a provider-specific gateway source and supports project or company ownership; Slack provisions one without creating a generic webhook trigger ([`app/models/webhook_endpoint.rb`](../../app/models/webhook_endpoint.rb), [`app/services/slack/integration_service.rb`](../../app/services/slack/integration_service.rb)). Generic webhook trigger creation does create both an endpoint and a `webhook.*` binding in the triggers controller ([`app/controllers/api/v1/projects/workflows/triggers_controller.rb`](../../app/controllers/api/v1/projects/workflows/triggers_controller.rb)).

YouTrack follows Slack's provider-endpoint pattern: connection setup creates one `provider: youtrack`, `verification_strategy: shared_token` endpoint with `config.integration_id`; it does **not** create a hidden `kind: webhook` binding. User-created bindings retain their explicit `youtrack.*` event types and `integration_id`. Add `youtrack` to the endpoint provider enum and make `shared_token` read the configured header name (the current verifier already implements constant-time shared-token comparison, but its `config_header` hook needs wiring; [`app/services/webhooks/signature_verifier.rb`](../../app/services/webhooks/signature_verifier.rb)).

GitHub keeps a dedicated signed controller and Slack has a dedicated ingress controller because they have provider-wide callback conventions. YouTrack fits the generic slug gateway because it has a per-project shared-token header and needs a distinct endpoint per connection ([`app/controllers/webhooks/ingress_controller.rb`](../../app/controllers/webhooks/ingress_controller.rb), [`app/controllers/webhooks/github_controller.rb`](../../app/controllers/webhooks/github_controller.rb), [`app/controllers/webhooks/slack_controller.rb`](../../app/controllers/webhooks/slack_controller.rb)).

### 5.2 Routing for project and company scope

```text
POST /webhooks/in/<random slug>
  → enabled WebhookEndpoint
  → config.integration_id
  → active Integration
  → enabled TriggerBindings visible to the binding project
     where binding.integration_id = integration.id
     and binding.event_type = normalized event type
```

Do not route through `Integration.project`. For a company integration, the matching bindings naturally span the company's projects; for a project integration, validation limits bindings to that project. `TriggerEvent.project_id` and `company_id` are already optional, and `TriggerBinding.for_event` already fans company events across company projects ([`app/models/trigger_event.rb`](../../app/models/trigger_event.rb), [`app/models/trigger_binding.rb`](../../app/models/trigger_binding.rb)). Persist a company-scoped event with `company_id`; each `TriggerDispatch` records the specific matched binding/run and its unique key is per event+binding.

The payload `project.id` must equal the selected YouTrack project ID, but this is only a consistency/integrity check. Anyone holding URL and token controls the body. The security boundary is the random URL plus project token; there is no body signature, nonce, or timestamp replay window.

No uniqueness constraint is added to `(base_url, youtrack_project_id)`. The same YouTrack project may feed several Aixle integrations/workflows. All destinations share the YouTrack project token; isolation rests on distinct unguessable URLs. Events for uncovered or mismatched projects are dropped.

## 6. Trigger contract

### 6.1 Shared settings

Each binding belongs to one workflow/project and selects one active visible integration. Reuse:

- `name`, `enabled`, `trigger_mode`, `cooldown_seconds`;
- `filter_predicate`;
- `subject_policy`: `none`, `existing_task`, or `create_task`, with existing `subject_column_id` and `subject_title_template`; and
- new required `integration_id` for `youtrack.*`.

`TriggerBinding` and `TriggerEngine#resolve_subject` already implement all three subject policies, task creation and title templating ([`app/models/trigger_binding.rb`](../../app/models/trigger_binding.rb), [`app/services/trigger_engine.rb`](../../app/services/trigger_engine.rb)). Extend subject resolution for YouTrack with the external-resource lookup in §9. `existing_task` uses the linked active task; when none is linked it follows the existing no-subject result and does not create a task. `create_task` always creates a new task and adds a new link, even when another linked task exists; this preserves the semantics of several workflows/projects intentionally creating separate work items.

Slack text match is represented as `filter_predicate.text` and evaluated by the shared `TriggerFilter`; its UI supports the existing equality/contains/regex semantics ([`app/frontend/pages/Projects/Workflows/TriggerFormPanel.tsx`](../../app/frontend/pages/Projects/Workflows/TriggerFormPanel.tsx), [`app/models/trigger_binding.rb`](../../app/models/trigger_binding.rb)). YouTrack reuses those fields/components and puts the relevant text in normalized `data.text`; no YouTrack-specific match columns are added.

### 6.2 Explicit trigger definitions

#### `youtrack.issue.created`

- Source: `issueCreated`.
- Conditions: valid endpoint/token; active selected integration; payload project ID matches; event has issue database/readable IDs. No mention check.
- Settings: all shared settings. **Text match is supported** against `summary + "\n\n" + description` using Slack semantics; blank means any created issue. Subject policies are supported, including `create_task`.
- Normalized data: integration/project IDs, issue IDs/link, actor ID/login, source event, occurred-at, `summary` (truncated), `description` (truncated), and `text` (the truncated combined text).
- Run context: same identifiers/actor plus truncated summary/description. Full current issue data is read with `youtrack_get_issue`.
- Dedup: `SHA-256(endpoint_id, "issueCreated", issue.id)`; an issue is created exactly once and its database ID is unique. Excluding the timestamp prevents a payload rebuilt during redelivery from starting a second run. The dispatch key adds binding ID, so one event legitimately starts each matching workflow once.

#### `youtrack.comment.mentioned`

- Source: `commentAdded`.
- Conditions: valid endpoint/token; active selected integration; matching project; comment text contains exact `@<bot_login>` with username-token boundaries; comment author is not the connected identity.
- Settings: all shared settings. Text match further filters the comment using Slack equality/contains/regex semantics; the mandatory bot mention is independent of this optional filter. All Subject policies are supported.
- Normalized data: integration/project IDs, issue and comment IDs/link, actor ID/login, source event, occurred-at, and truncated `text`/comment text.
- Run context: same identifiers/actor plus truncated triggering comment and extracted mention text. Full issue/comments are read with `youtrack_get_issue` and `youtrack_get_issue_comments`.
- Dedup: `SHA-256(endpoint_id, "commentAdded", comment.id)`; a comment has stable identity, so payload timestamp changes do not retrigger it. A later comment mentioning the bot is intentionally a new run; cooldown remains the only cross-comment suppression.

No issue-updated, issue-description mention, state/board transition, comment-update, saved-query, typed field filter, debounce, storm-policy, or per-trigger budget fields ship in V1. Company/project concurrency and spend controls remain authoritative.

### 6.3 Ingress, storage, outbox, and context

The current generic ingress stores raw JSON in `ReceivedWebhook.raw_payload` before asynchronous normalization ([`app/controllers/webhooks/ingress_controller.rb`](../../app/controllers/webhooks/ingress_controller.rb), [`app/models/received_webhook.rb`](../../app/models/received_webhook.rb)). That is unsuitable for catch-all data minimization. Add a YouTrack-specific normalization/redaction branch at ingress:

1. resolve endpoint; enforce POST/JSON and body-size ceiling;
2. verify shared token in constant time;
3. parse a bounded payload and classify event;
4. drop unsupported kinds immediately, with no `ReceivedWebhook` or `TriggerEvent`;
5. validate project ID and active integration;
6. detect the bot mention and evaluate whether at least one binding could match;
7. drop unsupported/unmatched bodies;
8. for matched events, persist a **redacted but sufficient** `ReceivedWebhook`: identifiers, event/timestamp, actor, and only bounded/truncated supported text; then enqueue processing.

There is no endpoint/IP rate limit in V1. Keep the body-size ceiling and cheap pre-persistence rejection.

`Webhooks::ProcessEventJob` converts the accepted record to `TriggerEvent`. The event's `data` contains the same bounded fields needed for filter evaluation and run construction; therefore data survives the accept/job boundary and outbox redelivery. `TriggerEngine.publish` persists `TriggerEvent` as the transactional outbox, while `TriggerDispatch` uniquely suppresses a repeated event+binding launch ([`app/jobs/webhooks/process_event_job.rb`](../../app/jobs/webhooks/process_event_job.rb), [`app/services/trigger_engine.rb`](../../app/services/trigger_engine.rb), [`app/models/trigger_dispatch.rb`](../../app/models/trigger_dispatch.rb), [`app/services/outbox_relay.rb`](../../app/services/outbox_relay.rb)).

Add `TriggerEngine#youtrack_run_context` alongside `slack_run_context` and pass `{"youtrack": ...}` to `WorkflowService.start`. The native board context includes only the first 500 characters of a task description and directs agents to board tools for complete task data ([`app/services/context_builders/board_context.rb`](../../app/services/context_builders/board_context.rb)); Slack currently carries triggering text in shared context ([`app/services/trigger_engine.rb`](../../app/services/trigger_engine.rb)). Apply that same 500-character limit independently to YouTrack summary, description, and triggering comment in event/run context; longer values end with a truncation marker and remain available live through tools. Use the same constant for the created task body renderer so subject creation cannot re-expand data.

Retention follows existing `ReceivedWebhook`, `TriggerEvent`, `TriggerDispatch`, and workflow-run policies; no YouTrack-only long-lived table is introduced. Never persist descriptions/comments from unsupported or unmatched callbacks, headers, tokens, or the original raw body. Log only IDs, event kind, endpoint/integration IDs and disposition.

## 7. Security, idempotency, storms, and lifecycle

- Authentication is possession of an unguessable endpoint and shared token. `shared_token` is constant-time, but provides no body signature or freshness. Payload project ID is not authentication.
- Exact duplicate callbacks are suppressed by the source keys above and the unique `TriggerEvent.dedup_key`; outbox replays are suppressed again by `TriggerDispatch.dedup_key`.
- A holder of both the unguessable URL and token can forge events with new issue or comment IDs; changing a created-event timestamp does not bypass the issue-created deduplication key. Project/company admission, concurrency and spend caps bound impact; secrets must be rotatable and logs never include them.
- Bulk creates can create many legitimate events. Cheap rejection, durable outbox, existing session admission and company/project spend/concurrency limits absorb the storm. There is no YouTrack-specific rate limiter.
- Revocation has no proactive signal. A runtime 401/403 returns a sanitized tool error without changing integration status, matching existing providers; reconnect-time validation can set `error`. Deleted issues return a normal not-found tool result. Project mismatch fails closed. Disconnect prevents new admission and tool calls; accepted audit rows remain. In-flight runs keep their context but tools of the disconnected integration become unavailable.
- Delivery is best-effort: if YouTrack cannot reach Aixle or does not retry, the event is lost. The UI must not promise lossless delivery.

Observability follows the existing webhook ingress and `TriggerEngine`: ordinary sanitized logging plus `last_received_at` on the integration screen as a callback diagnostic. “No trigger matched” and bad remote configuration remain indistinguishable until any callback arrives.

## 8. First-party MCP tools: one global set using Slack-style resolution

### 8.1 Registry and integration resolution

Register one global set of seven code tools named `youtrack_<operation>`. Every class declares `requires_integration :youtrack`; there is no integration selector argument, connection-listing tool, per-integration row, dynamic reconciliation, or per-row visibility. This is the existing Slack model: its global tool classes declare `requires_integration :slack` and share `InternalTools::Concerns::SlackContext` ([`app/services/internal_tools/slack_post_message.rb`](../../app/services/internal_tools/slack_post_message.rb), [`app/services/internal_tools/concerns/slack_context.rb`](../../app/services/internal_tools/concerns/slack_context.rb)). Extract/reuse the provider-integration selection helper where practical so YouTrack does not copy the ordering logic.

The YouTrack context resolver reads `workflow_run.shared_context["youtrack"]`. If that context contains `integration_id`, it selects that active integration within the session project's company, preserving the exact connection that admitted a YouTrack-triggered run. Otherwise it selects an active integration visible to the session project in this order: project-level (`project_id == project.id`), then company-level (`project_id IS NULL`). This exactly follows `SlackContext#slack_integration`, whose query orders project scope before company scope ([`app/services/internal_tools/concerns/slack_context.rb`](../../app/services/internal_tools/concerns/slack_context.rb)). Missing, inactive, disconnected, wrong-company, or no-project cases fail closed with a sanitized tool error.

Every tool request and every returned issue is checked against `issue.project.id == integration.settings.youtrack_project_id`; search results are filtered/rejected by the same invariant before returning them. Credentials are decrypted server-side for the resolved integration only and never enter agent context, environment, arguments, or tool output.

### 8.2 Known ambiguity and workflow duplication

Outside a YouTrack-triggered run, if a project can see several active YouTrack integrations at the same ownership level, selection is implicit: the resolver's first matching record wins, just as it does today for Slack and Coder. This is a known v1 limitation; the product does not expose multiple-connection selection until that rare use case is designed separately. Logs include the resolved integration ID for diagnosis.

Workflow duplication needs no YouTrack-specific logic. These are global platform/code tools, so `DependencyCopier#copy_tool` passes their IDs through unchanged through its `platform_tool?` branch ([`app/services/workflow_duplicator/dependency_copier.rb`](../../app/services/workflow_duplicator/dependency_copier.rb)).

### 8.3 Global tool surface

Register this single tool set:

| Tool | Purpose |
|---|---|
| `youtrack_search_issues` | Search only within the resolved integration's selected project; paginated summaries. |
| `youtrack_get_issue` | Read one issue with fields and description after project check. |
| `youtrack_get_issue_comments` | Paginated comments for a checked issue. |
| `youtrack_add_comment` | Create a comment as token owner. |
| `youtrack_update_issue` | Update allowed ordinary/custom fields, including State and Assignee. |
| `youtrack_manage_issue_tags` | Add/remove tags on a checked issue. |
| `youtrack_list_project_users` | Paginated exact IDs/logins usable for assignee values or mentions. |

Attachments, links, issue creation/deletion and comment editing remain deferred. YouTrack tools never operate on Aixle cards; `board_*` tools remain separate. Native YouTrack MCP is not used because it cannot enforce the selected-project check in Aixle code and would place the token in external MCP headers.

## 9. External resources and data model

### 9.1 Generic external-resource links

Add `external_resources`, a generic child table of `BoardTask`:

```text
external_resources
  id                  bigint PK
  board_task_id       bigint NOT NULL FK board_tasks ON DELETE CASCADE
  type                varchar NOT NULL       # "youtrack_issue" in Phase 2
  external_instance   varchar NOT NULL       # normalized YouTrack base URL
  external_id         varchar NOT NULL       # YouTrack database issue ID
  data                jsonb NOT NULL DEFAULT {}
  created_at/updated_at

UNIQUE (board_task_id, type, external_instance, external_id)
INDEX  (type, external_instance, external_id, board_task_id)
```

The resource identity is defined by the external system, independently of the Aixle connection used to observe it. For `youtrack_issue` it is `(type, external_instance, external_id)`: YouTrack database IDs are immutable within one instance but need not be globally unique. `external_instance` is the base URL produced by the same `url.to_s.strip.chomp("/")` normalization as the integration setting in §4.4.

The non-unique lookup index permits one external object to link to several Aixle tasks. The unique constraint only prevents the same resource link being inserted twice on one task. `BoardTask has_many :external_resources`. The integration used to create a link may be retained only as optional diagnostic metadata such as `data.created_via_integration_id`; it is not identity, is not a foreign key, and never cascades on integration deletion.

For `youtrack_issue`, `external_id` is `issue.id` (database ID), never the readable `APP-123`. `data` is written once when the link is created and contains only routing/display metadata: readable ID, YouTrack project database ID, source `workflow_id`/binding ID, and optionally the ID of the integration through which the link was created. Workflow and binding IDs intentionally remain in `jsonb`; the indexed identity lookup narrows candidates to the Aixle tasks created for this one issue—normally one and occasionally a few—so project/workflow filtering over those rows does not justify dedicated columns. The browser URL is built from `external_instance` and the readable ID. Summary, description, fields, comments, attachments, users, or status are never copied into this table. Other future types can define their own identity and data without being required to belong to an integration.

Creation of a task under a YouTrack binding's `create_task` policy and insertion of its resource link occur in the same transaction. Replayed dispatch cannot duplicate either because `TriggerDispatch` remains unique and the link has the constraint above. `create_task` always creates a distinct task/link even when another link exists: multiple workflows and projects are legitimate independent work streams, and silently reusing a task would change the configured Subject policy.

For `existing_task`, use the identity index to find candidates by resource type + normalized instance + issue database ID, then restrict through `board_task.project_id` to the current binding's Aixle project. Prefer an active task whose link's `data.workflow_id` matches the binding's workflow; if several exist for that workflow, choose the oldest link as its stable canonical subject. If there is no same-workflow candidate, use the sole active project candidate. If none exists, resolve no subject; if several cross-workflow candidates exist, also resolve no subject and record an `ambiguous_external_subject` diagnostic rather than attach the wrong task. A company-level and a project-level integration that point at the same normalized instance/project see the same project-local links after reconnect or credential replacement. Different Aixle projects still see only their own board tasks.

The run context adds linked task ID, title, URL, column, archived state, and the same 500-character description excerpt used by native board context, alongside YouTrack integration/issue/comment data. Full task content remains available through `board_*`; full issue content remains live through that integration's YouTrack tools.

Lifecycle edges are intentionally narrow:

- deleting an Aixle task cascades its links; archived tasks do not take part in subject resolution;
- moving a YouTrack issue between YouTrack projects is not supported in V1;
- after a YouTrack instance changes its domain, existing links are no longer found; this is not supported in V1;
- deleting a YouTrack issue leaves a harmless link until its Aixle task is deleted; live tools return not found;
- disconnecting, replacing, or deleting an integration retains links; it prevents admission and tools through that connection, while a later valid connection to the same normalized instance/project can resolve the existing links;
- links are one-way external-resource → Aixle task identity. They do not create imports, field mirroring, sync, or ownership of the external object.

### 9.2 Other model changes

- enum additions: `Integration.provider = youtrack`, `WebhookEndpoint.provider = youtrack`;
- nullable `trigger_bindings.integration_id` FK/index, required by validation for `youtrack.*`, plus ownership/provider/visibility checks;
- integration encrypted credential/settings keys from §4.5;
- endpoint `config.integration_id`, encrypted webhook secret, configurable shared-token header;
- `external_resources` and associations/constraints from §9.1;
- `BoardTaskResource` external-resource serialization and the read-only Details-tab list from §9.3.

`TriggerEvent` and `TriggerDispatch` are not structurally changed. Add provider normalization/context code and retention-safe redaction. No YouTrack content, subscription, polling, or webhook-rate-limit table is introduced.

### 9.3 Phase 2 sequence

1. **Connection/client:** enums, settings/credentials, both ownership scopes and policies/UI; hardened REST client; identity/project validation; manual setup instructions.
2. **Ingress:** endpoint provisioning, shared-token header support, bounded YouTrack early classifier/redactor, two normalizers, source dedup and lifecycle cleanup.
3. **Triggers/resources:** `integration_id`; exact two event types; reuse Slack text matching and Subject controls; instance-based external-resource creation/resolution; linked-task run context and truncation.
4. **Tools:** one global seven-operation `youtrack_*` group with `requires_integration :youtrack`, shared Slack-style resolver logic, selected-project request/response checks, and lifecycle/precedence tests.
5. **Task Details UI:** expose `external_resources` from `BoardTaskResource` as read-only `{ type, readable_id, url }` entries and render them below the CI Gates block in the task Details tab. The existing task show/index API already serializes through `BoardTaskResource` ([`app/controllers/api/v1/projects/board/tasks_controller.rb`](../../app/controllers/api/v1/projects/board/tasks_controller.rb), [`app/resources/board_task_resource.rb`](../../app/resources/board_task_resource.rb)); preload links on the board query to avoid N+1 reads. Show only type, readable identifier (for example `APP-123`), and a safe external link; no add/edit/remove controls. The insertion point is the existing `CI Gates (N)` block in [`app/frontend/pages/Projects/Board/BoardPage.tsx`](../../app/frontend/pages/Projects/Board/BoardPage.tsx).
6. **Hardening/docs:** lifecycle behavior, secret rotation, retention, ordinary logging, fixtures for duplicate/outbox/fan-out/company+project overlap and reconnect/link persistence, plus SSRF/DNS/redirect tests.

Expected affected areas are `Integration`, `WebhookEndpoint`, `TriggerBinding`, `BoardTask`, the new `ExternalResource`, integration management UI/controllers/policies, webhook ingress/job, `TriggerEngine`, internal tool registry/classes, and migrations/tests. There are no founder decisions left open and no deviation from review A–J or the v4 review.

## 10. Acceptance and approval gate

Phase 1 is complete when this v6 is attached and explicitly reviewed. Phase 2 must not begin without Alex's approval. No production code, branch, tests, or PR are part of this revision.

Implementation acceptance follows this document: both ownership scopes connect; exact two triggers configure and fire; matched text survives durable dispatch in bounded context; unmatched/unsupported bodies are not stored; duplicates do not double-launch; external-resource links survive reconnect and resolve only within instance/project rules; task Details shows their read-only identity/link; global YouTrack tools resolve the trigger-context/project/company integration in order; all tools enforce selected-project scope; and disconnect fails closed without importing or mirroring content.
