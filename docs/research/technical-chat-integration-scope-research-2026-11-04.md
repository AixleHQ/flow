# Chat integration scope: company-wide or per project — research

**Date:** 2026-11-04
**Status:** Option C's install scope decided and built on 2026-11-04 (§9). Channel-connection scope
(option B) not built.
**Code baseline:** `542b2949`
**Question:** Earlier work concluded that messenger integrations (Slack, Microsoft Teams) must be
company-wide. Is that still true? Could whoever sets up a chat integration choose between "this
project only" and "the whole company"?
**Related:** [design/shared-chat-workspaces.md](../design/shared-chat-workspaces.md) (#199, decision 15),
[design/teams-integration.md](../design/teams-integration.md) §2,
[technical-slack-chatops-integration-research-2026-06-25.md](./technical-slack-chatops-integration-research-2026-06-25.md),
[technical-slack-multi-tenant-workspace-routing-design-2026-06-28.md](./technical-slack-multi-tenant-workspace-routing-design-2026-06-28.md),
[design/task-tracker-integrations.md](../design/task-tracker-integrations.md) §4.4 (the "project-only"
precedent).

## TL;DR

- **The claim is half right.** A chat integration has two layers, and they have different answers:
  1. **The install** binds a workspace or a Microsoft 365 tenant to a company. It holds the OAuth or
     admin consent, the bot token, the events endpoint and the uninstall path. The company is the
     right owner. Making installs per project would mean a Microsoft 365 admin approval per project
     and rework of the dedup and fan-out keys (§5, option D).
  2. **The channel connection** decides which channels a project's triggers listen to and its agents
     reach. Nothing forces this to be company-wide. Decision 15 of #199 made it so as a product
     choice ("the tenant is the isolation boundary"), not because of a constraint.
- **The original technical reason is gone.** Slack became company-wide on 2026-06-28 (commit
  `19aab0e0`) because the endpoint `slack-team-<team_id>` was unique and owned by one project, so a
  second project could not use the same workspace. Since #199 phase 2, `chat_workspaces` and per-channel
  routing remove that constraint.
- **The data already knows the project.** `chat_connect_codes.project_id` is `NOT NULL`. The
  redemption throws it away: `Chat::ChannelConnect` writes the connection keyed by
  `(conversation, company)` only (`app/services/chat/channel_connect.rb:95`).
- **Recommendation: option B, optionally C.**
  - **B:** give each channel connection a scope, "this project" or "the whole company", chosen in the
    connect dialog. The change is small and covers most of the isolation value.
  - **C:** additionally let the install be "available to this project only", the way trackers already
    allow. That is your "at setup time" choice. It needs an extra rule: one install per
    (company, workspace).

## 1. Where "company-wide" came from

| Date | Source | What it said | Why |
|---|---|---|---|
| 2026-06-25 | `technical-slack-chatops-integration-research` | "the bot is configured **once per project**" | Slack was a per-project `Integration` with a pasted signing secret |
| 2026-06-28 | commit `19aab0e0` "add company wide integrations" + migration `ScopeSlackInstallsToCompany` | "A Slack workspace install belongs to a COMPANY and serves all its projects" | The endpoint slug `slack-team-<team_id>` was globally unique and owned by **one** project, so a second project could not attach the same workspace. Company scope was the cheapest way to get "one workspace, many projects" |
| 2026-06-28 | `technical-slack-multi-tenant-workspace-routing-design` | Phase 1: "company-level fan-out (safe base)" | The same endpoint constraint. The doc itself says this is "an internal decision, not a Slack limit" |
| 2026-09-30 | `teams-integration.md` §2 | "Company-wide `Integration(provider: teams)`, one per Entra tenant" | Copied the Slack rule. The tenant binding is proven by a Microsoft 365 admin, inside a flow a company admin started |
| 2026-10-22 | `shared-chat-workspaces.md` decision 15 | "A connection is company-wide. Any project of the company can post to the channel or bind a trigger to it. The tenant is the isolation boundary." | Product choice. The same doc, under "Not taken": "Within one company both are valid as they are" |

So the hard constraint behind company-wide existed only between 06-28 and #199 phase 2. What remains is
decision 15, and that was a product choice.

## 2. Each reason checked against today's code

| Reason given or implied | Still true? | Evidence |
|---|---|---|
| One events endpoint per workspace, owned by one tenant | **No longer forces scope.** The endpoint is workspace-owned. `Chat::WorkspaceRouter` fans out to every peer install, and `TriggerBinding.listening_in` routes by channel | `app/services/chat/workspace_router.rb`, `app/models/trigger_binding.rb:147` |
| One bot token per workspace | True, but this is about the install, not about who uses it. Peer installs already share one token | `Slack::IntegrationService#share_token_with_peers` |
| Teams: a Microsoft 365 admin approves each company (decision 14) | **True.** Per-project installs would multiply admin approvals. This argues for keeping the install at company level, not the channels | `app/services/teams/connection.rb` (`start!` per company) |
| Rate limits are per workspace | True, and unaffected by scope | — |
| Triggers are project-scoped, events company-scoped | True. `for_event` fans a chat event out to all projects of the company, then filters by channel connection, which is checked by **company** | `trigger_binding.rb:76-91, 147-157` |
| "The tenant is the isolation boundary" | Product choice. Nothing in the code needs it | `shared-chat-workspaces.md` §2.15 |

## 3. What company-wide means today, concretely

For every company that connected a workspace:

- **Installing.** Any member who can write to a project (`IntegrationsPolicy#manage_integrations?` →
  `project_writable?`) installs Slack for the **whole company**. Removing it needs a company admin
  (`IntegrationsController#destroy`, `current_project_membership.admin?`; despite the name, that is the
  company membership). Connecting is easier than undoing, and connecting affects more than the
  project it was started from.
- **Connecting a channel.** Anyone who manages a project's triggers asks for a code (decision 16). The
  channel is then connected to the company, not to the project that asked.
- **Triggers.** A trigger in any project can bind to any channel the company connected. The
  `listening_in` check joins `chat_channel_connections` to `projects` on `company_id`.
- **Agent tools.** `Chat::ChannelAccess.channels(project)` returns every channel connected to the
  company. An agent in project A can post to, edit in and read threads of a channel that project B
  connected for itself (`chat_post_message`, `chat_read_thread`, …).
- **Help in a channel** lists the triggers of every project listening there
  (`Chat::HelpCatalog#bindings`).
- **`/run` and the Run workflow action** list workflows from every project of the person's companies
  that share the workspace (`Chat::RunCatalog#active_projects`). This one is already limited by the
  person's own project permissions, so it is not a leak.
- **Disconnecting** a channel or uninstalling releases the triggers of every project in the company
  (`Chat::ChannelDisconnect`, `Integration#release_chat_triggers`).

The common shape on the hosted deployment is one company running several unrelated teams' projects
off one workspace. With company-wide connections, an HR or hiring channel connected by one project is
reachable by agents of every other project in that company. That is the gap the requested option
closes.

## 4. Two layers, two answers

```text
Install  (Integration, provider slack|teams)       workspace ↔ company trust
  OAuth / Microsoft 365 admin consent, bot token,  → company is the natural owner
  events endpoint, uninstall, rate limit             (optionally narrowed to one project: option C)
  │
  └── Channel connection (chat_channel_connections) which project reaches which channel
        triggers bind to it, agent tools reach it  → project or company, chosen per connection
                                                     (option B)
```

This is the same split the tracker design made (`task-tracker-integrations.md` §4.4): one
company-held connection holds the credential, with a per-project unit on top (`ProjectTracker`). The
connection's creator can also keep it project-only (`project_id` set), and then no other project can
link it.

## 5. Options

### A. Keep the status quo

- **Cost:** none.
- **Downside:** no isolation between projects of one company. Any project writer connects channels
  for everyone.

### B. Scope on the channel connection — recommended

- **Model.** `chat_channel_connections.project_id`, nullable. `NULL` means the whole company,
  which is what every existing row keeps. A set value means that project only.
- **Uniqueness.** A channel can be connected to several projects of one company, or once
  company-wide:
  - one partial unique index on `(chat_conversation_id, company_id)` where `project_id IS NULL`;
  - one on `(chat_conversation_id, company_id, project_id)` where `project_id IS NOT NULL`.
  - A company-wide row makes the project rows for that channel redundant. Widening replaces them.
- **Choice point.** The connect dialog (`ConnectChannelModal.tsx`) gets "Only this project /
  Whole company". The code record already carries `project_id`, so redemption only has to keep it:
  `chat_connect_codes` gains a `scope` column, and `ChannelConnect` writes `project_id` from the code.
- **Enforcement points**, each changing "connected to the company" into "connected to the company
  for this project or for everyone":
  - `TriggerBinding.listening_in`: add `AND (connections.project_id IS NULL OR connections.project_id = trigger_bindings.project_id)`;
  - `ChatConversation.connected_to_company` → a `connected_for(project)` scope, used by
    `Chat::ChannelAccess.channels` (agent tools, the channel picker, `list_chat_channels`) and
    `Chat::TargetResolver`;
  - `Chat::HelpCatalog` already works from matching bindings, so it follows `listening_in`;
  - `Chat::ChannelDisconnect` and `Integration#release_chat_triggers` release only the bindings the
    removed row served;
  - the `chat_messages` ledger stays per company. It guards update and delete between companies, and
    within one company the tool check above already applies.
- **The bot's public reply** still names only the company (decision 22). A project name never
  appears in the channel.
- **Migration.** None needed for behavior: existing rows are `NULL`, which means company-wide as
  today.
- **Cost:** small to medium. Roughly one migration, about six backend touch points, one dialog
  control, and tests on each touch point.

### C. B plus install scope ("available to this project only")

What you described: decide at setup whether the integration lives inside the project or company-wide.

- **Model.** A Slack or Teams `Integration` may keep `project_id` set, as trackers allow. Most read
  paths already use `Integration.visible_for_project`, so a project-only install is invisible to other
  projects (`ChannelAccess`, `ConnectCodes.issue!`, `TargetResolver`, the tool gate).
- **Rule that keeps routing simple.** One install per (company, workspace), whatever its scope. A
  second project of the same company that wants the workspace asks for it to be widened to the
  company, which needs a company admin. Without this rule a company could hold a company-wide row and
  a project-only row for one workspace:
  - `WorkspaceRouter` would publish twice for one company;
  - the dedup suffix `:c<company_id>` would collide.
- **Extra touch points:**
  - `Slack::IntegrationService#find_or_build_for_team` filters on `project_id: nil` and builds with
    `project: nil`;
  - `Teams::Connection.start!` builds with `project: nil`;
  - `WorkspaceRouter#publish_for` publishes with `project: install.project` when it is set, because
    `for_event` already narrows to `event.project_id`;
  - `Chat::RunCatalog#active_projects` narrows to the install's project;
  - `Chat::HelpCatalog#listening_projects` follows the same narrowing;
  - widening and narrowing an existing install becomes an edit action on the integration card.
- **Teams.** Narrowing does not change the tenant approval: it is still one approval per company,
  per decision 14.
- **Cost:** medium, on top of B.

### D. Fully per-project installs (each project its own row, peers per project)

- **Not recommended.** Every project would need its own OAuth install or Microsoft 365 admin
  approval. The dedup key and the peer model would move from company to project. Disconnect, uninstall
  and project move would all need rework. Options B and C give the same isolation without any of that.

## 6. Interactions to settle before building

- **Project move.** Today moving a project to another company releases its chat triggers. A
  project-only connection could follow the project when the target company has an install of the
  same workspace. That is a follow-up. V1 releases as today.
- **Shared workspaces (#199 phase 2).** Unchanged: isolation between companies still comes from the
  company's own install and connections. Project scope only narrows within a company.
- **Agents posting to an unconnected channel** keep the existing refusal. The message should say
  "not connected to this project" when the channel is connected to the company for other projects
  only.
- **Templates and MCP.** `create_chat_connect_code` gains an optional `scope`. No typed channel ids,
  per decision 3.

## 7. Open questions for the product owner

1. **Default scope for a new channel connection:** this project (least privilege) or the whole
   company (today's behavior)?
2. **Who may make a connection company-wide:** anyone who manages the project's triggers (decision 16
   as is), or a company admin only?
3. **Install scope (option C):** is it needed in v1, or does channel scope (B) cover the need?
4. **Who may install for the whole company:** should a company-wide install still be possible for any
   project writer, given that removing it needs a company admin?

## 8. Touch points (option B)

| File | Change |
|---|---|
| `db/migrate/*` | `chat_channel_connections.project_id` (nullable FK); partial unique indexes; `chat_connect_codes.scope` |
| `app/services/chat/channel_connect.rb:95` | write `project_id` from the code's scope |
| `app/models/trigger_binding.rb:147` (`listening_in`) | project-or-company condition |
| `app/models/chat_conversation.rb:22` (`connected_to_company`) | add `connected_for(project)` |
| `app/services/chat/channel_access.rb` | use `connected_for(project)`; refusal text |
| `app/services/chat/target_resolver.rb` | same narrowing for Teams targets |
| `app/services/chat/channel_disconnect.rb`, `app/models/integration.rb` (`release_chat_triggers`) | release only the bindings the row served |
| `app/services/chat/connect_codes.rb`, `ChatConnectCode.issue!` | accept and store `scope` |
| `app/frontend/shared/resources/chat-channels/ConnectChannelModal.tsx`, `ChatChannelsModal.tsx` | scope control; show scope per channel |
| MCP `create_chat_connect_code`, `list_chat_channels`; `Api::V1` equivalents | optional `scope`; listing per project |
| `docs/user-guide/slack.md`, `docs/user-guide/teams.md`, `docs/design/shared-chat-workspaces.md` §2.15 | amend decision 15 |

## 9. Decision and what was built (2026-11-04)

The product owner chose the install scope of option C, with a permission rule, and no channel scope:

- **Company-wide is the default, and a company admin's.** Connecting Slack or Teams for the whole
  company, renewing a company-wide Teams approval link, and sharing a project's install with the
  company need a company admin (`User#admin_of?`). Anyone else who can change the project connects
  it for that project. Question 4 of §7 is answered: no.
- **The choice is made when connecting.** A dialog on the project's Integrations page asks "Every
  project in the company" or "Only this project". Slack carries it in the signed OAuth `state`
  (`company_wide`), rechecked at the callback. Teams gets it as `scope` on `teams_connect`.
- **One install per (company, workspace), widened and never narrowed.** Connecting a workspace
  that another project of the company holds is refused. Connecting it for the whole company, or
  the row's "Share with the whole company" action (`PATCH …/integrations/:id` with
  `scope=company`), widens a project install. A company-wide install is never narrowed.
- **Routing.**
  - `Chat::WorkspaceRouter` publishes a project install's event with its project, so
    `TriggerBinding.for_event` matches that project only.
  - `Integration.served_projects` narrows `Chat::HelpCatalog` and `Chat::RunCatalog`.
  - `TriggerBinding#chat_connected?` and `#chat_channel_problem` require an install the trigger's
    project can see.
  - `Chat::ChannelConnect` refuses a code asked for in another project.
- **Project move.** A project's own Slack or Teams install is switched off, and its workspace is
  released (`Integration#release_chat_workspace!`), as the Azure DevOps install already was.
- **Channel connections stay company-level** (decision 15). Questions 1–2 of §7 stay open for
  option B.
