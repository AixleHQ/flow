# Slack multi-tenant workspace routing — design

Status: design / proposal (no code yet)
Date: 2026-06-28
Related: `ai/research/technical-slack-chatops-integration-research-2026-06-25.md`

## Goal

Let one Slack workspace's events drive workflows in many places:

1. **Multi-project (same company)** — connect a workspace once, have several projects react to their own channels.
2. **Multi-company (cross-tenant)** — an outsourcing team wants their workspace to also drive a *client's* company in Aixle, when (and only when) the workspace owner explicitly allows it, scoped to specific channels.

Driving requirement from the product owner: "be able to connect everything everywhere — maybe extract Slack endpoints as their own thing, separate from companies and projects." That is the right structural move; this doc makes it concrete and adds the authorization layer that decoupling alone does not provide.

## Why this is an internal decision, not a Slack limit

Aixle runs **one Slack app per deployment**: one bot, one bot token per workspace, one shared Request URL (`POST /webhooks/slack/events`). No matter how many Aixle tenants want a workspace, there is exactly one bot in it. So "route to N tenants" is purely **our** routing + authorization decision — not something Slack constrains.

## Current architecture (as-is) and the one block to remove

- `Integration` (provider `slack`) is bound to `(company, project)`. Bot token in encrypted `credentials_data`; `team_id` mirrored to `settings`.
- `WebhookEndpoint` slug `slack-team-<team_id>` is **globally unique** and **owned by one company + one project**. Inbound events route by `team_id` to this single endpoint → `endpoint.project`.
- `Webhooks::ProcessEventJob` publishes a `TriggerEvent(project: endpoint.project)`; `TriggerBinding.for_event` matches bindings **only** in that one project; `TriggerEngine.dispatch` skips when `event.project_id` is blank.
- `Slack::IntegrationService#foreign_company_owns_workspace?` hard-blocks a second company from claiming the same `team_id`.

**Key enabler already in place:** `TriggerEngine#fire_for_binding` runs the workflow in **`binding.project`** (the trigger's own project/company), *not* the endpoint's project. So once matching fans out, execution is already correctly per-project / per-company. The only thing tying a workspace to a single tenant is the *endpoint ownership* and the *project-scoped matching*.

## Core idea: a standalone `SlackWorkspace` entity

Promote the workspace from "a field on an Integration/Endpoint" to a first-class, tenant-agnostic resource. Companies/projects *attach* to it via explicit connections.

### Data model

```
SlackWorkspace                         # one row per Slack workspace (team_id)
  team_id            :string  uniq     # the routing key
  team_name          :string
  bot_user_id        :string
  credentials_data   :encrypted        # the single bot token (lives here, once)
  installed_by_user  :ref              # who ran OAuth
  owner_company      :ref              # the installer's company = admin of this workspace
  status             :enum  active|inactive|revoked
  scopes             :string           # granted Slack scopes

SlackWorkspaceConnection               # workspace <-> company link (the consent grant)
  slack_workspace    :ref
  company            :ref
  channel_ids        :string[]         # [] = none; explicit allow-list. NO implicit "all".
  allow_all_channels :boolean = false  # loud, admin-only escape hatch (discouraged)
  inbound_enabled    :boolean = true   # can this company's triggers fire on this workspace?
  outbound_enabled   :boolean = true   # can this company post to this workspace?
  granted_by_user    :ref              # owner-company admin who created the grant
  accepted_by_user   :ref  null        # grantee admin who accepted (handshake), null until accepted
  status             :enum  pending|active|revoked
  uniq (slack_workspace_id, company_id)
```

- The owner company gets an **auto `active` connection** to its own workspace on install (with `allow_all_channels` or the channels the bot is in).
- Every other company needs an **owner-granted, channel-scoped, revocable** connection.
- `TriggerBinding` stays per-project (project → company). A Slack trigger fires only if the binding's company has an `active` connection to the event's workspace **and** the event's channel is in that connection's allow-list.

The single `WebhookEndpoint`/route stays as the one Request URL; it stops being company/project-owned and simply resolves a `SlackWorkspace` by `team_id`. (We can keep `WebhookEndpoint` as the generic gateway and point it at a `SlackWorkspace`, or fold its Slack role into `SlackWorkspace`. Either works; folding is cleaner for Slack specifically.)

> Trade-off vs. the unified `Integration` model: Slack is genuinely special (one shared bot, multi-tenant shareable) where GitHub/GitLab/Coder are per-project credential blobs. A dedicated `SlackWorkspace` + connections models that honestly. Alternative: keep `Integration` but make the slack one company/project-agnostic and add the connections join. Recommended: dedicated model.

## Inbound routing (fan-out)

On `slack.message` (app_mention) for `team_id` + `channel`:

1. Resolve `SlackWorkspace` by `team_id`. If none/inactive → ack & ignore.
2. Candidate companies = every `SlackWorkspaceConnection` that is `active`, `inbound_enabled`, and whose `channel_ids` include `channel` (or `allow_all_channels`).
3. Match `TriggerBinding`s across the **projects of those companies** (event_type + `filter_predicate`), and fire each in its own project (`fire_for_binding` already does this).
4. Dedup unchanged: one dispatch per `(event, binding)` → N matching bindings → N runs, each in its project/company.

**Channel is the router.** A project claims channels via its trigger's channel filter; cross-company, the *connection's* `channel_ids` is the outer gate (a company can only ever see channels its grant allows).

Engine changes required:
- `TriggerEvent` carries the workspace (and not a single owning project). Add `slack_workspace_id` (or keep project nil and match by workspace).
- `TriggerBinding.for_event` for Slack: match across the connected companies' projects, intersected with the per-connection channel allow-list — instead of `where(project_id: event.project_id)`.
- `dispatch` must not early-return on blank `event.project_id` for workspace-scoped events.

## Outbound (replies / file uploads)

- There is exactly one bot token (on `SlackWorkspace`). `slack_post_message` / uploads for **any** connected company resolve the workspace by the run's `shared_context["slack"]["team"]` and post through that single token.
- The token is **never copied** into a grantee company's records — outbound is mediated by `SlackWorkspace`.
- Outbound is restricted to channels the company's connection allows (`outbound_enabled` + `channel_ids`), so a grantee can't post into channels it wasn't granted.

## Ownership & consent UX

- **Install** (OAuth) → creates `SlackWorkspace` owned by the installer's company + an auto active connection.
- **Grant**: owner-company admin: "Share workspace W with company X, channels [#a, #b]" → creates a `pending` connection. Optional **handshake**: X's admin accepts → `active`. (Handshake recommended for cross-company; intra-org grants can auto-accept.)
- **Revoke**: owner (or grantee) flips connection to `revoked` → takes effect immediately (checked at routing time).
- **Audit**: log connection create/accept/revoke and every cross-company dispatch (which workspace → which company/project/run).

## Security threats & mitigations

| Threat | Mitigation |
|---|---|
| Cross-tenant data leak (messages/files into a foreign tenant) | Channel-scoped connections; only allow-listed channels route to a grantee. No implicit "all". Private channels must be added explicitly. |
| Bot-token exposure to grantee | Token lives only on `SlackWorkspace`; outbound mediated; never copied per-tenant. |
| Trigger hijack / unsolicited attach | A company can attach only via an owner-created grant; optional grantee handshake; revocable. |
| Over-broad grant | `allow_all_channels` is admin-only + surfaced loudly; default is an explicit channel list. |
| File ingestion across tenants | Same channel-scope gate; existing size/type/SSRF caps still apply. |
| Stale access after offboarding | Revocation checked at routing time (not cached); deactivating the workspace cascades to all connections. |
| Confused-deputy (grantee posts as the bot anywhere) | Outbound restricted to the connection's channels + `outbound_enabled`. |

**Recommendation:** treat cross-company sharing as a deliberate, narrow, audited grant — not a default. For most cases, the cleaner and safer pattern is still: each org installs the bot into **its own** workspace (1 workspace : 1 company). Cross-company sharing is for the explicit outsourcing case only.

## Phasing

1. **Phase 1 — company-level fan-out (safe base).** Extract `SlackWorkspace`; owner company + its projects; route by channel across the company's projects. Keep the 1-workspace-1-company block. No cross-tenant surface. This already delivers "same workspace, many projects".
2. **Phase 2 — cross-company connections.** Add `SlackWorkspaceConnection` grants (channel-scoped, consented, revocable, audited); relax `foreign_company_owns_workspace?` to "owner OR has an active connection"; mediate outbound; add consent UX.

## Migration

- Introduce `SlackWorkspace`; backfill one per existing `slack` `WebhookEndpoint` (`team_id`, token from the linked `Integration`, owner = endpoint.company), plus an auto active connection for that company.
- Repoint `ProcessEventJob` resolution from endpoint→project to `team_id`→`SlackWorkspace`→connections.
- Keep the existing `/webhooks/slack/events` route and signature verification unchanged.

## Open questions

- Handshake required for cross-company, or owner-only grant enough?
- Channel discovery UX (list channels the bot is in vs. free-text channel IDs).
- Per-connection rate limiting / quotas for shared workspaces.
- Should `TriggerBinding` reference a `SlackWorkspaceConnection` explicitly (tighter) vs. resolve by channel at fire time (looser)?
