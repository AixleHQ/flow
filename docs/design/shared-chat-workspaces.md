# Shared chat workspaces and channel-bound chat triggers — technical design

**Status:** Direction agreed 2026-10-22: decisions 1–23 (§2), no open questions. Phases 1 and 2 built
(§20, §21). Spikes S3 and S4 (§15.3) still want a live check on staging.
**Board task:** #199, "Make channel selection required when launching a trigger via Slack".
**Code baseline:** `715fc7c0`
**Audience:** backend, frontend and operations engineers
**Related:** [teams-integration.md](./teams-integration.md) (the messaging port this builds on: `chat.message`,
`chat_*` tools, `shared_context.chat`, the conversation registry, account linking);
[technical-slack-multi-tenant-workspace-routing-design-2026-06-28.md](../research/technical-slack-multi-tenant-workspace-routing-design-2026-06-28.md)
(an earlier owner-and-grants proposal for the same problem, not taken — §16);
[user-guide/slack.md](../user-guide/slack.md), [user-guide/teams.md](../user-guide/teams.md).

## 1. Goal

1. **One chat workspace, many companies.** A Slack workspace or a Microsoft 365 tenant can be connected to
   several Aixle companies at once. Today each one belongs to exactly one company.
2. **No company owns the workspace.** Every company connected to it is a peer. The only authority above them
   is the Slack or Microsoft 365 admin, who lives outside Aixle.
3. **A company reaches only the channels connected to it.** Isolation is enforced on the server, on every
   path: inbound messages, agent tools, status replies, files, help and self-service commands.
4. **Every chat trigger listens to exactly one channel** (#199). A trigger without one cannot be switched on.

Terms used below:

| Term | Slack | Teams |
|---|---|---|
| **Workspace** | a Slack workspace (`team_id`) | a Microsoft 365 tenant (`tid`) |
| **Channel** | a public or private channel | a channel, or a group chat |
| **Direct chat** | a DM with the bot | a 1:1 (personal) chat with the bot |
| **Connection** | a channel connected to one company | same |

`@Aixle` below stands for the deployment's bot as people see it in the messenger: `@aixle-flow` in production
Slack, "Aixle Flow" in Teams. Every deployment has its own name, so Aixle never hard-codes it in text (§8.1).

## 2. Decisions

Agreed in the #199 discussion on 2026-10-21 and 2026-10-22:

1. **Peers, no owner.** Companies connected to one workspace are equal. Nothing in Aixle grants one company
   control over another's access.
2. **One channel per trigger.** A chat trigger carries exactly one channel. It cannot be enabled without
   one. Listening in three channels means three triggers.
3. **A channel enters Aixle only from inside the channel.** Aixle issues a one-time code. Someone posts
   `@Aixle connect <code>` in the channel, and the bot connects the channel the message came from. A typed
   channel id is never accepted, from the UI, the API, MCP or a template. Aixle learns a channel's id only
   from an event that Slack or Teams delivered from that channel.
4. **The proof is that a member of the channel posted the code.** Slack and Teams deliver a message only from
   someone who can write in that channel.
5. **A forwarded code is fine.** Someone in the channel chose to post it, and the bot answers publicly in the
   channel (§8.3). That reply is the trace.
6. **Public channels are allowed** on the same terms: anyone in the workspace can join one, and the public
   reply shows the connection.
7. **A connection belongs to the company, not to the person.** Leaving the channel or the company changes
   nothing. If the connection needs redoing, someone connects the channel again.
8. **The connect dialog tells people to invite the bot first.** The bot only sees channels it is in.
9. **Every gap found in review is in scope** (§3.4): routing keys in trigger conditions, agent tools,
   per-company fan-out and dedup, the shared install's lifecycle, write paths that skip the checks, and rate
   limits.
10. **Slack and Teams work the same way.** The mechanism is provider-neutral and ships for both.
11. **Every connection starts in Aixle.** It is requested from the trigger form, the integration card, MCP or
    the API. Slack and Teams only ever carry the code back. Nothing in the messenger starts a connection.
12. **The migration splits triggers that listen in several channels.** This applies to a chat trigger with no
    channel that has fired from several channels:
    - the trigger keeps the channel it fired from most;
    - each other channel gets a copy of the trigger with the same settings, named `<name> (2)`, `<name> (3)`;
    - a trigger that never fired becomes "needs a channel" (§15.2).
13. **Production's existing channels are connected silently.** No announcement is posted for them. Today
    each workspace has one company, so there is no one to warn.
14. **Teams: each company connecting a tenant needs a Microsoft 365 admin's approval**, as the first one
    does today (§7.2).
15. **A connection is company-wide.** Any project of the company can post to the channel or bind a trigger
    to it. The tenant is the isolation boundary.
16. **Anyone who may manage a project's triggers can request a code.** It is not limited to company admins.
    The connection is announced publicly anyway.
17. **A company never sees which other companies share its workspace.** It sees only its own channels.
18. **Slack asks for `channels:read` and `groups:read`**, so Aixle can show channel names. They are added in
    the reinstall already owed for #425 (§8.4).
19. **Removing a connection is announced in the channel**: "**Acme** disconnected this channel" (§8.3).
20. **No per-company share of Slack's rate limit in v1.** Each company is handled the same (§11.5).

Decided 2026-10-22 after a design review:

21. **A code names its channel.** Whoever asks for a code says which channel it is for: Slack
    `#deploys` or `deploys`; Teams `Team / Channel` (every team has a General), or a group chat's name.
    Posted anywhere else the code connects nothing, and it still works where it belongs. This replaces
    a confirm-in-Aixle step: a code left in a channel the bot is not in cannot be carried to another one.
22. **The bot's public messages name the company and the command, never a person or a project.** A
    channel may hold guests and other organizations. `help` lists each trigger's command and workflow,
    plus its company when several share the channel.
23. **A refusal is private, and a code is kept as an HMAC.** Slack shows a refused code only to whoever
    posted it (ephemeral); Teams, which cannot, says it at most once a minute per person. The stored
    digest is keyed with a server secret, so a copy of the database does not give a live code back.

Not taken from the same review: a separate "read any thread" level on a connection, and announcing or
re-confirming the channels the migration connected. Within one company both are valid as they are, and
a connection into another company is announced in its channel anyway.

## 3. What exists

### 3.1 Inbound routing today

- **Slack.** `Webhooks::SlackController#events` finds the endpoint by `team_id`:
  `WebhookEndpoint.active.find_by(slug: "slack-team-<team_id>")`. `Webhooks::ProcessEventJob` normalizes the
  payload with `Chat::SlackProvider.normalize`, which keeps `app_mention` events only. It then calls
  `TriggerEngine.publish(company: endpoint.company, project: nil)`.
- **Teams.** `Webhooks::TeamsController` finds `teams-tenant-<tid>`, drops every message that does not
  address the bot before storing anything, and publishes the same way.
- **Matching.** `TriggerBinding.for_event` fans a company-scoped `chat.message` out to the active chat
  bindings of every project in that company. `TriggerFilter` then applies `filter_predicate`.
- **Dispatch order** (`TriggerEngine.dispatch`):
  1. help;
  2. Teams `/run` and `/status` (targeted or 1:1 only);
  3. the targeted-message hint;
  4. binding match;
  5. the help catalog when nothing matched.

### 3.2 Where the channel lives today

- **Storage.** The channel is a plain key in `filter_predicate`: `{"provider": "slack", "channel": "C…",
  "text": {...}}`. Event data carries the same id three times: `channel`, `conversation.id` and `subject`.
- **Slack form.** The trigger form has a free-text "Channel id" field, placeholder "blank = any"
  (`TriggerFormPanel.tsx:1497`).
- **Teams form.** Teams gets a picker fed from `chat_conversations` (`Chat.trigger_options`), with "Anywhere"
  and "Direct messages" options.
- **Every other write path** accepts any `filter_predicate`: `Api::V1::Projects::Workflows::TriggersController`
  (`filter_predicate: {}`), the `create_workflow_trigger` / `update_workflow_trigger` MCP tools and template
  install.

### 3.3 One workspace, one company

The rule is enforced in four places:

- `Slack::IntegrationService#foreign_company_owns_workspace?` refuses a second company ("This Slack workspace
  is already connected to another organization").
- `Teams::Connection#bind!` refuses when `teams-tenant-<tid>` points at another integration ("That Microsoft
  365 organization is already connected to an Aixle workspace").
- `webhook_endpoints.slug` is unique, and the endpoint carries `company_id` plus `config.integration_id`.
- The Slack bot token lives in the company's `Integration.credentials_data`. Teams uses one bot token per
  deployment and a Graph token per tenant (`Teams::TokenService`).

### 3.4 Gaps that matter here

| # | Gap | Where |
|---|---|---|
| G1 | A channel id is not a secret. Public channel ids are visible to every workspace member, and ids travel in links, mentions and exports. | Slack/Teams behaviour |
| G2 | A condition can match every channel: `{"channel": {"op": "present"}}`, `regex`, `ne`, or the same id under `conversation.id`. | `TriggerFilter`, dot-paths |
| G3 | `chat_read_thread`, `chat_post_message`, `chat_update_message` and `chat_delete_message` accept any Slack channel id and call Slack with the workspace's bot token. | `InternalTools::Concerns::SlackContext#resolve_slack_target` |
| G4 | `trigger_events.dedup_key` is `slack:<event_id>`, unique across the whole table. A second company's copy of the same event would be dropped silently. | `ProcessEventJob`, `TriggerEngine.publish` |
| G5 | Templates export a trigger's channel id, and installing the template puts it in another company's project. | `Templates::Exporter#binding_entry`, `Templates::Installer#create_trigger` |
| G6 | Template setup activation and archive restore enable a trigger with `update!`, skipping `save_checking_chat!`. | `Templates::SetupChecklist#activate_trigger!`, `Workflow#unarchive!` |
| G7 | Moving a project to another company keeps its triggers' channel ids. | `ProjectMove::Mover` |
| G8 | Disconnecting a workspace disables the Slack endpoint and deletes the Teams endpoint, along with the Teams conversation registry. With several companies this would cut off everyone. | `Integration#release_slack_workspace`, `#release_teams_tenant`, `has_many :chat_conversations, dependent: :delete_all` |
| G9 | `app_uninstalled` / `tokens_revoked` deactivates one integration. | `Webhooks::SlackController#deactivate_install` |
| G10 | `Chat::RunCatalog`, `RecentRuns`, both `AccountLink`s and `ChatLinksController` assume one company per workspace (`integration.company_id`). | `app/services/chat/`, `app/services/{slack,teams}/account_link.rb` |
| G11 | The help catalog lists triggers that have no channel in every channel of the workspace. | `Chat::HelpCatalog.bindings` |
| G12 | A Slack trigger set to "Direct messages" never fires. Slack events always carry `conversation.type: "channel"`, DMs give no `app_mention`, and `im:history` is not requested. | `Chat::SlackProvider.normalize` |
| G13 | `Slack::Client` has no rate-limit handling. Only status cards retry `ratelimited`. With one install per workspace, the limit is shared by every company. | `Slack::Client`, `Slack::StatusCard` |

## 4. Production snapshot

Read-only queries against the hosted deployment's database, 2026-10-21 and 2026-10-22. This repository is
public, so the snapshot gives shapes, not names, ids or counts:

- **Workspaces.** Each connected workspace serves one company. Nothing is shared yet.
- **Chat triggers.** All are Slack, written by many different authors. Most name exactly one channel. A few
  name none:
  - one matches on text alone and has fired from several channels;
  - one filters only on the sender, and has never fired;
  - one is set to "Direct messages", and has never fired, because it cannot (G12).
- **Channels used only for posting.** Many workflows name channels in their step instructions that no trigger
  listens on: scheduled reports and digests. Channels used only for posting are a real pattern, not an edge
  case (§8.5).
- **Senders.** Almost none of the people who mention the bot have linked their Slack account.
- **Teams.** Connected, with no Teams triggers yet.

The low link rate rules out anything that depends on people linking their accounts first (§16).

## 5. Shape of the change

```
chat_workspaces (Slack team / M365 tenant) ── bot credentials, endpoint, tenant-level consent
   │  1─n
   ├── integrations (one per company that connected the workspace) ── no credentials
   │  1─n
   └── chat_conversations (channels, group chats, direct chats seen by the bot)
          │  1─n
          └── chat_channel_connections (channel ↔ company) ── made only by redeeming a code in the channel
                 │  1─n
                 └── trigger_bindings.chat_conversation_id (exactly one, same company)
```

- **Inbound.** A message is routed to the companies connected to the channel it came from, and to no one else.
- **Outbound.** A company's agents, cards and files reach only the channels connected to it, plus the thread
  its run started from.

## 6. Data model

### 6.1 `chat_workspaces` (new)

| Column | Notes |
|---|---|
| `provider` | `slack` \| `teams` |
| `external_id` | Slack `team_id` or Microsoft `tid`. Unique per `(provider, external_id)` |
| `name` | team name or tenant domain |
| `status` | `active` \| `inactive` (uninstalled or revoked in Slack) |
| `credentials` (encrypted) | Slack: `bot_token`, `bot_user_id`, `scope`. Teams: none (§3.3) |
| `bot_name` | the name people type to mention the bot (§8.1). Slack: `auth.test` → `user`, read at install and reconnect. Teams: not stored; it is the app's short name |
| `settings` | Teams: `file_access`, `file_access_checked_at`, `catalog_*`. These are tenant-level facts and move here from the integration |

- **Endpoint.** The `slack-team-<id>` / `teams-tenant-<tid>` endpoint belongs to the workspace:
  `company_id: nil` and `config.chat_workspace_id`. `webhook_endpoints.company_id` is already nullable.
- **Token.** The Slack bot token is stored once, on the workspace, and never copied to a company.

### 6.2 `integrations` (changed)

- **New column.** `chat_workspace_id`: a company's link to a workspace, one row per (company, workspace).
- **Unchanged.** The row keeps what is per company: `connected_by`, `status`, and Teams' `approved_by` /
  `approved_at` for that company's approval.
- **Credentials move.** Slack `credentials_data` moves to the workspace. Every reader of
  `credentials_data["bot_token"]` goes through the workspace instead.

### 6.3 `chat_conversations` (changed: the channel registry)

- **Re-keyed by workspace.** It is keyed by `chat_workspace_id` instead of `integration_id`: unique
  `(chat_workspace_id, external_id)`. Rows are shared by every company on the workspace, and a row by itself
  grants nothing.
- **Slack gets rows.** A row is written when a channel is connected (§8) and when an event arrives from a
  known channel.
- **`external_id`.** The canonical channel id: the Slack channel id, or the Teams conversation id with any
  `;messageid=` suffix removed. `ChatConversation.record_teams!` today prefers `channelData.channel.id` for
  channels while `Chat::TeamsProvider.normalize` strips the suffix; both must produce the same key (§15,
  spike S2).
- **`kind`.** `channel`, `group` or `direct`. A `direct` row is never connectable.

### 6.4 `chat_channel_connections` (new)

| Column | Notes |
|---|---|
| `chat_conversation_id`, `company_id` | unique together |
| `requested_by_id` | the Aixle user whose code was redeemed |
| `posted_by_external_id`, `posted_by_name` | the Slack or Teams user who posted the code |
| `message_url` | permalink to the bot's public confirmation |
| `connected_at` | |

### 6.5 `chat_connect_codes` (new)

| Column | Notes |
|---|---|
| `company_id`, `project_id`, `provider` | where the code may be redeemed, and for which messenger |
| `trigger_binding_id` (nullable) | when requested from a trigger, the trigger to bind on success |
| `code_digest` | SHA-256 of the code. The code itself is never stored |
| `requested_by_id`, `expires_at`, `redeemed_at`, `chat_channel_connection_id` | |

- **Code format.** `aixle-` plus 8 Crockford Base32 characters: 40 bits.
- **Lifetime.** Single use, valid for 10 minutes.
- **Cap.** At most 10 unredeemed codes per company.

### 6.6 `trigger_bindings` (changed)

- **New column.** `chat_conversation_id`, required for an enabled `chat.message` binding (§9.1).
- **Routing keys leave `filter_predicate`.** `channel`, `conversation.*`, `workspace.*`, `team`,
  `integration_id`, `subject` and `service_url` move out (§9.2). What remains is `provider`, `text` and
  sender conditions (`user`, `actor.id`).

## 7. Connecting a workspace

Connecting a workspace gives a company nothing by itself: no channel, no messages. Only connecting a channel
(§8) does. That is why joining an already-connected workspace can be easy.

### 7.1 Slack

1. **OAuth unchanged.** The install ("Add to Slack", `oauth.v2.access`) is the same as today. It proves the
   person is a member of the workspace who may install apps there.
2. **Workspace upsert.** `Slack::IntegrationService#create_from_oauth` upserts `chat_workspaces` by `team_id`
   and stores the token Slack returned, then creates or reactivates this company's `Integration`.
   `foreign_company_owns_workspace?` and the "already connected to another organization" refusal go away.
3. **Token on reinstall.** We expect a reinstall of the same app in the same workspace to return the same bot
   token. Spike S1 verifies this. If it does not, the latest token wins, since it is the workspace's only token.
4. **Endpoint.** The endpoint is created once per workspace and never reassigned to a company.

### 7.2 Teams

1. **Same approval for each company.** Each company goes through the existing approval:
   - someone who may manage the company's integrations starts it;
   - a Microsoft 365 admin signs in with a directory role (`wids`).
2. **Bind to the workspace.** `Teams::Connection#bind!` attaches the integration to the tenant's
   `chat_workspaces` row, creating it on the first approval. The "already connected to an Aixle workspace"
   refusal goes away.
3. **Tenant-level consents happen once per tenant.** Catalog publishing is skipped when the workspace already
   has the current version. `Files.ReadWrite.All` consent is recorded on the workspace.
4. **The admin's approval stays required for every company** (decision 14). The tenant-wide file permission
   and the catalog are tenant matters, and the Microsoft 365 admin is the authority outside Aixle that
   decision 1 relies on.

### 7.3 Disconnecting a company

- **What it removes.** `Integration#destroy` removes that company's link and its channel connections in that
  workspace. Its chat triggers become "needs a channel" (§9.1).
- **What it never touches.** The endpoint, the token, the conversation registry and other companies' rows.
  `release_slack_workspace`, `release_teams_tenant` and `dependent: :delete_all` move to the workspace.
- **Last company.** When the last company disconnects, the workspace is kept `inactive` with its token
  dropped, so the registry survives a reconnect.
- **No Slack or Teams call.** Disconnecting does not call Slack or Teams, as today. Uninstalling the app is
  done in Slack or Teams.

### 7.4 Uninstall and revocation

- **Slack.** `app_uninstalled` and `tokens_revoked` mark the workspace `inactive`. Every connected company
  sees "Slack app removed from &lt;workspace&gt;: reinstall to resume".
- **Reinstall.** A reinstall by any one of the companies reactivates the workspace for all of them. This is
  inherent to one app install per workspace.
- **Teams.** Removing the app from a team marks that team's conversation rows `installed: false`, as today.
  The rows stay shared.

## 8. Connecting a channel

### 8.1 Requesting a code

- **Who can request.** Anyone who may manage the project's triggers can request a code (decision 16):
  - from the trigger form ("Connect a channel"), which binds the trigger on success;
  - from the integration card ("Connect a channel" for posting only, §8.5).
- **Precondition.** The company must already have connected a workspace for that messenger.
- **What the dialog shows**, with the bot's real name filled in. The production Slack example:
  1. Invite the bot first: `/invite @aixle-flow`. In Teams: "add **Aixle Flow** to the team or group chat".
  2. In the channel, type `@aixle-flow` and pick it from the list. Then paste `connect aixle-7F3K9QXM`, which
     has a copy button.
  3. A 10-minute countdown, and a live status that the page polls until the code is redeemed or expires.
- **Where the name comes from.**
  - Slack: `chat_workspaces.bot_name`, from `auth.test` (no extra scope), stored at install and on every
    reconnect. Existing installs are backfilled the same way.
  - Teams: the app's short name from `Teams::AppPackage` (`"Aixle Flow"`), the same name the catalog shows.
  - Nowhere else in the UI or in bot replies is the name written by hand.
- **Why "pick it from the list".** Teams treats a typed or pasted `@name` as plain text: no `<at>` tag and no
  mention entity. The message is then dropped as unaddressed (teams-integration.md, live traps). For Slack,
  spike S4 checks whether a pasted `@aixle-flow` becomes a mention. Until then the same instruction stands.
  The command part never depends on the name: redemption strips the bot's mention by its id, not by its text.
- **MCP and API.** They get the same operation (§14.3). An agent receives the code and relays the
  instruction to a person.

### 8.2 Redeeming

Redemption runs at the workspace step of inbound routing (§10.1), before help, commands and matching:

1. **Recognize the request.** After the leading bot mention is stripped, the text matches
   `\Aconnect\s+aixle-[0-9A-HJKMNP-TV-Z]{8}\z` (case-insensitive). Teams needs the mention entity, as for any
   addressed channel message.
2. **Reject direct chats.** A DM or 1:1 chat is refused: "Post it in the channel you want to connect".
3. **Look up the code.** By digest: unredeemed and unexpired, and for this provider.
4. **Check the workspace.** The code's company must have an active integration on this event's workspace.
5. **Record the connection.** Upsert the `chat_conversations` row, then create the `chat_channel_connections`
   row unless it already exists. If the code carries a trigger, set its `chat_conversation_id` and enable it
   if it was waiting.
6. **Close the code.** Mark it redeemed and write an audit record.
7. **Reply publicly** in the thread (§8.3).

A bare `@Aixle connect` without a code is not a request (decision 11). The bot answers: "Request a code in
Aixle: Integrations → Slack → Connect a channel."

Every failure (another channel than the code names, unknown, expired, already used, another messenger,
company not on this workspace) gets the same reply, shown only to whoever posted it (decision 23): "This
code is not valid here or has expired. Request a new one in Aixle." The person who requested the code
sees the precise reason in Aixle, and the channel learns nothing about other companies.

### 8.3 The public confirmation

The bot answers in the thread, visible to everyone in the channel:

> This channel is now connected to **Acme**.
> @Aixle deploy here starts one of **Acme**'s workflows.

It names the company and what starts the trigger, and no person or project (decision 22).

A channel connected for posting only (§8.5) gets the second line in this form instead:

> **Acme**'s workflows can post here.

- **What it is.** This message is the trace that decisions 5 and 6 rely on. Its permalink is stored on the
  connection.
- **Disconnecting.** Removing a connection in Aixle posts a matching "**Acme** disconnected this channel" (decision 19).
- **Removing the bot.** Removing the bot from the channel stops delivery for every company, which is the
  channel members' own kill switch. Agent calls then fail with `not_in_channel` and are reported as such.

### 8.4 Provider specifics

**Slack**
- **What can be connected.** Public and private channels, wherever the bot is a member.
- **Routing.** `app_mention` already carries `team_id`, `channel` and `user`. Nothing new is needed to route
  the code.
- **Channel names** (decision 18). `channels:read` and `groups:read` join the bot scopes, in the reinstall
  already owed for #425 (`commands`):
  - redemption reads the name with `conversations.info`;
  - `channel_rename` and `group_rename` events keep it current.

  A workspace that has not reinstalled yet answers `missing_scope`. Aixle then shows the channel id, and
  Slack still renders `<#C…>` as the name in Slack itself.

**Teams**
- **What can be connected.** Channels and group chats where the app is installed (RSC).
- **Commands.** `Teams::Commands` only acts on targeted messages or 1:1 chats, so `connect` is handled before
  commands and matching, the same way help is.
- **Names.** These come from `channelData` and `Teams::WelcomeJob`, as today.

**Both**
- **Reserved word.** `connect` becomes reserved, like `help` (`Chat::RESERVED_COMMAND`) and Teams' `run` /
  `status`. A trigger whose text command is `connect` is refused, and the migration checks for existing ones.

### 8.5 Channels used only for posting

- **Connecting one.** A channel can be connected with no trigger listening on it, from the integration card
  ("Connect a channel"), MCP or the API. Scheduled reports and digests need this (§4).
- **What the connection gives.** It lets the company's agents post, read threads and send files there
  (§11.1). It starts nothing.
- **One connection serves both purposes.** It is the same record for posting and for triggers. A channel
  connected for a trigger can also be posted to, and a channel connected for posting can later be chosen by
  a trigger.
- **How agents name it.** Step instructions name a channel by name ("post to #reports"). The tools resolve
  names among the company's connected channels only (§11.1).

### 8.6 Removing a connection

- **Who.** Company admins, or anyone who can manage the company's integrations, remove a connection from the
  integration card.
- **Effect on triggers.** Triggers bound to it lose their channel and switch off, as "needs a channel".

## 9. Triggers

### 9.1 One channel, required to switch on

**The invariant.** An enabled `chat.message` binding has a `chat_conversation_id` that is:
- connected to the binding's company;
- of the binding's messenger, and not `direct`.

Whether the install is active is not part of it. An uninstalled app or a removed team stops the
messages arriving, and a reinstall brings every trigger back as it was; saving a trigger meanwhile
still works.

**Enforced as a model validation.** It is a validation, not a check on one save path, so every write path
inherits it: web, API, MCP, template activation and archive restore (G6). Each event that would break the
invariant switches the affected triggers off and clears their channel in the same transaction, so the
validation never fails a save for reasons the person cannot see:

| Event | Effect on bound triggers |
|---|---|
| A connection is removed | lose the channel, switched off |
| A company disconnects a workspace | lose the channel, switched off |
| A trigger moves to another messenger (`assign_chat_provider`) | channel cleared, as today |
| A project moves to another company (G7) | channel cleared, switched off; the move preflight already lists them |

**"Needs a channel".** A disabled chat trigger with no channel shows a "Needs a channel" badge, and a list of
them is never an error (acceptance criterion 3).

### 9.2 Conditions

- **Routing keys are refused.** `filter_predicate` refuses `channel`, `conversation`, `conversation.*`,
  `workspace`, `workspace.*`, `team`, `integration_id`, `subject` and `service_url` for chat triggers. The
  error points at the channel field.
- **Isolation does not depend on this rule.** The router only ever hands a company events from its own
  connected channels (§10), so no condition can widen what a trigger sees (G2). The rule keeps one source of
  truth for "where".
- **What remains.** `text` (with its operators) and sender conditions (`user`, `actor.id`).

### 9.3 Write paths

| Path | Change |
|---|---|
| Trigger form | The free-text "Channel id", "Anywhere" and "Direct messages" go. A channel select lists the company's connected channels for that messenger, plus "Connect a new channel…" (§8.1) |
| API `triggers#create/update` | Accepts `chat_conversation_id` from the company's connected channels only. Routing keys in `filter_predicate` give 422 (§9.2) |
| MCP `create_workflow_trigger` / `update_workflow_trigger` | Same. The description stops suggesting `{"channel": "C123"}` |
| Template export | Drops the channel and adds a setup note "connect a channel after install" (G5) |
| Template install / setup activation | Installs disabled without a channel, as today. Activation goes through the validation (G6) and asks for a channel |
| Archive restore (`Workflow#unarchive!`) | Re-enables only triggers whose channel is still connected. The rest stay off as "needs a channel" (G6) |
| Project move | Clears channels and switches chat triggers off (G7). Admin copy: "connect channels in &lt;target&gt;" |
| `duplicate_workflow` | Unchanged: it does not copy triggers |

## 10. Inbound routing

### 10.1 The workspace step

A chat endpoint now resolves a workspace, not a company. `ProcessEventJob` normalizes as today, then hands the
event to a new `Chat::WorkspaceRouter`. The router does the workspace-wide work exactly once, in this order:

1. **Connect** (§8.2).
2. **Help**, detected as today (Slack `/help`; Teams `help` or `/help`). The catalog becomes "triggers bound to this channel, in any
   company", each line naming its company and project. Those connections were announced in the channel, so
   listing them reveals nothing new.
3. **Self-service commands.** Teams `/run` / `/status`, and Slack's slash command and shortcut on their own
   endpoints (§12).
4. **The targeted-message hint** (Teams).
5. **Fan-out** (§10.2).
6. **Nothing matched in any company.** The help catalog for this channel, answered once. If the channel is
   connected to nobody, the reply also says how to connect it.

Today these steps run per company inside `TriggerEngine.dispatch`. They move to the router, so that a shared
channel gets one help answer, not one per company.

### 10.2 Fan-out by channel

1. Find the `chat_conversations` row for (workspace, channel). A DM or 1:1 chat gets steps 1–4 only. It never
   reaches triggers.
2. Find the connected companies that have an active integration on the workspace.
3. Match each company's bindings: `active`, `chat_conversation_id` = this channel, workflow active, and
   `TriggerFilter` on what remains of `filter_predicate`.
4. Publish one `TriggerEvent` per company with at least one match. Set `company_id` to that company and
   `data.integration_id` to that company's integration. Dedup is per company (§10.3). From here the existing
   `TriggerEngine` takes over: dispatch per binding, status reporting, files.

**Why one event per company, and not one workspace-level event.** A stored event holds the message text.
With one row per company, every row lives inside one tenant: retention, admin views and audits never see
another tenant's data. A company with no matching trigger stores nothing.

### 10.3 Dedup

- **Delivery.** Unchanged: `received_webhooks` is unique per endpoint and idempotency key.
- **Event.** `dedup_key = "<provider>:<idempotency_key>:c<company_id>"`, which fixes G4.
- **Launch.** Unchanged: the `TriggerDispatch` key, event plus binding.

### 10.4 Who may trigger

Unchanged (teams-integration.md §7.6). Anyone who can address the bot in a connected channel can fire a
matching trigger, and the run belongs to the trigger's creator.

## 11. Outbound

### 11.1 Agent tools

The tools are `chat_read_thread`, `chat_post_message`, `chat_update_message` and `chat_delete_message`. Each
call's target must be one of:

- a channel connected to the run's company, in a workspace that company has connected; or
- the conversation and thread the run started from. That covers `/run` from a channel that is not connected:
  the person who ran it is a linked member who brought that thread in themselves.

Everything else is refused before any Slack or Teams call: "Channel not connected to &lt;company&gt;. Connect it in
Aixle (Integrations → Slack → Connect a channel)." The refusal does not depend on whether the channel exists,
so it reveals nothing.

- **Slack.** `SlackContext#resolve_slack_target` and `InstallResolver` resolve through the company's
  connections. The workspace is the run origin's when one exists, otherwise the one connected first, as today.
- **Teams.** `Chat::TargetResolver.teams` already scopes by the company's integrations. It narrows from "any
  registry row" to "connected rows plus the origin".
- **Agents learn the channel list.** The tools' descriptions and the run context list the company's connected
  channels by name, so an agent stops guessing ids from instructions.

### 11.2 Editing and deleting the bot's messages

- **The risk.** In a shared channel, the bot's own messages belong to several companies. Slack lets the bot
  edit any of them.
- **A small ledger.** `chat_messages` holds (workspace, channel, message id, company id, run id). It is written
  by `Slack::Notifier`, the status cards and `chat_post_message`.
- **The rule.** `chat_update_message` and `chat_delete_message` act only on messages that the run's company
  posted.

### 11.3 Status cards and failure notices

- **Unchanged.** They post to the origin thread as today.
- **Integration lookup.** `Slack::StatusCard#target` finds the integration by `data.integration_id` without
  scoping by company. The per-company event now carries the right integration, and the token comes from its
  workspace.

### 11.4 Files

- **Inbound.** Files are ingested only from the routed event, so they follow the fan-out. Each matched
  project already downloads its own copy.
- **Teams permission.** `Files.ReadWrite.All` stays a single tenant-wide consent, stored on the workspace.
  Code confines it, as teams-integration.md §8.5 describes:
  - reads come only from the triggering message's attachments;
  - writes go only to the origin channel's `Aixle/` folder.
- **Sharing a tenant adds no new read path.** The isolation comes from routing.

### 11.5 Rate limits (G13)

- **Shared limits.** Slack's limits are per app per workspace, so a single install's limits are shared by
  every company. Teams' Connector limits are per bot per conversation.
- **v1 handling:**
  - `Slack::Client` reads `Retry-After` on `ratelimited` and raises a typed error;
  - tools return `{error: "rate_limited", retry_after}` to the agent, as `teams_failure` already does;
  - status cards keep their retry job.
- **Not in v1.** There is no per-company fair share inside one workspace (decision 20). Rate-limited calls are
  logged with their company, so the question can be revisited on data.

## 12. Identity and self-service

- **Identities stay user-level.** `chat_identities` is keyed by (provider, workspace, user) with no company,
  and that does not change.
- **`/run`, the Run workflow shortcut and Teams' message extension.** They list workflows from every company
  that:
  - the linked user is an active member of; and
  - has connected this workspace.

  `Chat::RunCatalog.entries(user, workspace)` replaces `entries(user, integration)`. Entries name their
  company when there is more than one.
- **`/status`.** Same union of companies. The conversation filter is unchanged.
- **`Slack::AccountLink`, `Teams::AccountLink` and `ChatLinksController`.** Linking requires membership in
  any company connected to the workspace, not in one `integration.company`.
- **Workspace resolution.** Slack's slash command and interactivity resolve the workspace through
  `integration_for(team_id)`, then the person's companies.

## 13. Security

| Threat | Answer |
|---|---|
| Company B listens to company A's channel by learning its id (G1) | An id alone does nothing. A channel is connected only by a code posted inside it (§8.2), and the connection is announced there (§8.3) |
| Someone forwards a code to a channel member | Accepted (decision 5). Posting it is that member's choice, and the reply is public |
| Guessing a code | 40 bits, 10 minutes, single use, at most 10 open per company, and posting is rate-limited by Slack and Teams. A guessed code would connect the guesser's channel to the code's company: spam toward that company, not a leak from it |
| A condition that matches every channel (G2) | Routing hands a company only its connected channels' events (§10.2). Routing keys are refused in conditions (§9.2) |
| An agent reads or posts in an unconnected channel (G3) | Refused server-side before any provider call (§11.1). The bot token never leaves the server |
| Prompt injection pointing the agent at another channel | Same refusal. The agent can only reach the company's connected channels and its own origin thread |
| Company A edits or deletes company B's bot messages | The message ledger (§11.2) |
| A template carries a channel into another company (G5) | Channels are not exported |
| A project move carries channels into another company (G7) | Channels are cleared and the triggers switched off |
| Activation or restore skips the checks (G6) | The model validation covers every path (§9.1) |
| Dedup drops a company's copy of an event (G4) | Per-company dedup key (§10.3) |
| One company's disconnect cuts off the others (G8) | Endpoint, token and registry belong to the workspace (§7.3) |
| Uninstall in Slack | Stops the workspace for every company, inherently. Surfaced to all of them (§7.4) |
| A connect failure reply reveals other companies | One generic reply (§8.2) |
| Help reveals other tenants' trigger names | Only triggers bound to that channel, whose connections were announced there (§10.1) |
| One tenant exhausts the shared rate limit | v1: Retry-After plus typed errors, with no per-company share (decision 20) |
| Teams' tenant-wide `Files.ReadWrite.All` | Code-confined to the triggering message and the origin channel. Unchanged by sharing (§11.4) |

## 14. UI, API and MCP

### 14.1 Integration card (Slack and Teams)

- **Channels section.** For each connected channel: its name, who requested it, who posted the code, when,
  and a link to the public confirmation. Plus "Connect a channel" (§8.1) and "Disconnect" (§8.6).
- **Other companies are never shown** (decision 17).
- **Workspace status.** Shown when the app was removed in Slack, or file access was not granted in Teams.

### 14.2 Trigger form and list

- **Form.** A channel select (§9.3), and "Connect a new channel…" opening the code dialog. The dialog selects
  the channel when the code is redeemed.
- **List.** A "Needs a channel" badge, and the enable switch is disabled with a tooltip.

### 14.3 MCP and API

- **New operations:**
  - `create_chat_connect_code(project_id, provider, trigger_id?)` returns the code, its expiry and the line to
    post;
  - `get_chat_connect_code` returns its status;
  - `list_chat_channels(project_id)` returns the company's connected channels.
- **Changed tools.** `create_workflow_trigger` / `update_workflow_trigger` take `chat_conversation_id` and
  refuse routing keys.
- **Serializers.** `WorkflowTriggers::Serializer` returns `chat_channel: {id, name, provider}` instead of
  exposing the channel through `filter_predicate`.

## 15. Migration and rollout

### 15.1 Expand and contract

A rolling deploy runs old and new code side by side, so the change ships in steps:

1. **Expand.** Add the tables and columns. Backfill (§15.2) and write both shapes.
2. **Switch.** Routing reads `chat_conversation_id` and the router (§10). Tools enforce connections.
   Old pods still read `filter_predicate.channel`, which stays in place.
3. **Contract.** Strip routing keys from `filter_predicate`, move Slack credentials off `integrations`, and
   drop the old single-company checks.

### 15.2 Backfill

**Workspaces and integrations**
- One `chat_workspaces` row per Slack and Teams integration. Integrations and endpoints are pointed at it.

**Channels and connections**
- Channels come from every place they already appear:
  - trigger predicates;
  - step and sub-step instructions, matching channel-id-shaped tokens that contain a digit, so words like
    `CHECKLIST` are skipped;
  - `trigger_events` channels from the last 90 days;
  - run origins in `shared_context.chat`;
  - Teams `chat_conversations`.
- Each is connected to the company that already uses it, recorded as `requested_by: migration`.
- No announcement is posted (decision 13).

**Triggers**
- Bindings with a scalar `channel` get `chat_conversation_id`.
- Bindings without one are sorted by the channels they actually fired from, which are read from
  `trigger_dispatches` joined to `trigger_events.data.channel` (decision 12):
  - **None:** disabled, "needs a channel". This includes every Slack trigger set to "Direct messages", which
    never could fire (G12).
  - **One:** that channel.
  - **Several:** the binding keeps its most-used channel and its dispatch history. Each other channel gets a
    copy with the same workflow, conditions, mode, cooldown, reporting and author, enabled as the original was.
    Copies are named `<name> (2)`, `<name> (3)` and so on. The channel is shown on the trigger itself, so the
    name never has to carry it.

**No production data in the repository**
- The migration finds everything at run time from the database. Its code holds no channel ids or names, no
  trigger, company or project ids or names, and no counts.
- The same holds for its tests (made-up ids only), the changelog entry and the PR description.
- It logs counts only: workspaces, channels connected, triggers bound, split and switched off. It never logs
  ids or names.

**Reserved word**
- Any trigger using the word `connect` as its command is reported before the reserved word lands.

**Slack scopes** (decision 18)
- Add `channels:read,groups:read` to the default `SLACK_SCOPES` in `config/settings.yml`.
- Add them to production's explicit `SLACK_SCOPES` in aixle-infra, in the same change as the `commands` scope
  owed for #425.
- Every workspace reinstalls once. `docs/user-guide/slack.md` (the scopes table) and the self-hosted app
  manifest change with it.

### 15.3 Spikes

| # | Question | Where |
|---|---|---|
| S1 | Does reinstalling the same Slack app in the same workspace, from a second company's OAuth, return the same bot token, and does the old one keep working? | staging Slack app |
| S2 | For a Teams channel message, are `channelData.channel.id` and the conversation id with `;messageid=` stripped always equal, including the General channel? | staging tenant |
| S3 | Does a mention in a Slack private channel, and in a Slack Connect shared channel, arrive as `app_mention` with the expected `team_id`? | staging Slack app |
| S4 | Does a pasted `@<bot name> connect …`, not picked from autocomplete, arrive in Slack as `app_mention`? And does `auth.test` return the name people see in the composer? | staging Slack app |

## 16. Alternatives considered

| Alternative | Why not |
|---|---|
| **Owner company grants channels to others** (the 2026-06-28 research: `SlackWorkspace` + `SlackWorkspaceConnection` granted by the installer's company) | Makes one tenant the gatekeeper of the others. Rejected by decision 1 |
| **Channel id as the secret, typed into the trigger** | Ids are visible to every workspace member for public channels, and travel in links and mentions (G1). Leaving a channel cannot revoke the knowledge |
| **Verify the trigger author's membership** via a linked identity and `conversations.members` | Needs every author to link Slack first, and on the hosted deployment almost no one has (§4). It also needs new bot scopes |
| **Route by the sender's linked identity** (no channels at all) | The same linking problem. It also breaks "anyone in the channel can trigger" |
| **Match the Slack user to the Aixle user by email** | Contradicts teams-integration.md ("never by email"). Emails often differ, and it needs `users:read.email` |
| **One bot (Slack app) per company** | Isolation would come from Slack itself, but each company would need its own app and admin approval. Teams would need an Azure Bot and Entra app per company, which was dropped after spike 1 of the Teams design |
| **Starting a connection from the messenger** (`@Aixle connect` with no code → a private link to Aixle → pick a company) | Not wanted (decision 11): every connection starts in Aixle |
| **Enterprise Grid / Slack Connect / one workspace per tenant** | Not available to most customers, and Teams has no equivalent |

## 17. Open questions

None. All nine questions were decided on 2026-10-22 and are recorded as decisions 12–20 (§2):

| Was | Decision |
|---|---|
| Q1 | 12: the migration splits a trigger that fired from several channels |
| Q2 | 13: existing production channels are connected silently |
| Q3 | 16: anyone who can manage the project's triggers can request a code |
| Q4 | 17: a company never sees other companies on its workspace |
| Q5 | 14: Microsoft 365 admin approval for every company |
| Q6 | 18: Slack asks for `channels:read` and `groups:read` |
| Q7 | 19: disconnecting is announced in the channel |
| Q8 | 20: no per-company rate-limit share in v1 |
| Q9 | 15: connections are company-wide |

## 18. Phasing

**Phase 1 — #199, still one company per workspace.** Slack and Teams both, behind the existing one-company
rule:
- channel registry for Slack;
- connect codes and the public confirmation;
- channel required, with routing keys refused;
- write-path fixes (G5–G7);
- tool confinement (G3) and "connect for posting only";
- backfill.

**Phase 2 — shared workspaces.**
- `chat_workspaces`, and connecting an already-connected workspace for Slack and Teams;
- the workspace router with per-company fan-out and dedup (G4);
- workspace-owned endpoint, token and registry, with disconnect and uninstall reworked (G8, G9);
- the self-service union catalog (G10);
- the message ledger;
- rate-limit handling (G13).

Phase 1 is useful alone, and phase 2 stays small because the channel model is already in place.

## 19. Testing

Following [testing.md](../testing.md):
- **Model.** The §9.1 invariant on every write path (form/API, MCP, template activation, archive restore,
  project move, provider switch).
- **Router.** Code redemption: success, every failure reason with the same reply, a direct chat refused, both
  providers. Fan-out: two companies on one channel, a company not connected, a connected company with no
  match, per-company dedup.
- **Tools.** Refusal before any provider call for an unconnected channel. The origin thread is allowed. The
  message ledger guards update and delete.
- **Lifecycle.** A second company's Slack OAuth and Teams approval attach to the existing workspace. One
  company's disconnect leaves the others working. Uninstall reaches every company.
- **Frontend.** The channel select, the code dialog states, and the "needs a channel" badge.

## 20. Phase 1 as built

Built on branch `artempartos/triggerfish`, still one company per workspace. Where
it differs from the sections above:

- **Data.** `chat_channel_connections`, `chat_connect_codes` and
  `trigger_bindings.chat_conversation_id`, as in §6.4–§6.6. `chat_conversations`
  stays keyed by integration; re-keying it by workspace waits for
  `chat_workspaces` in phase 2. Slack rows are written when a channel is
  connected (`ChatConversation.record_slack!`).
- **The confirmation's trace.** The connection keeps the bot's message id
  (`confirmation_message_id`) rather than a permalink, which would need another
  Slack call.
- **A code asked for a trigger binds it, nothing more.** The trigger gets the
  channel, but switching it on stays an explicit step for whoever owns it.
- **What counts as a connect request.** Only `connect` on its own or
  `connect aixle-…`. "connect the repo to staging" is a request for a workflow
  and reaches the triggers.
- **Matching.** `TriggerBinding.for_event` routes a chat message by its channel
  (`.listening_in`: bound to that conversation, connected to the trigger's
  company). `#matches?` then ignores `channel`.
- **The copy in conditions.** The model keeps a copy of the channel id in
  `filter_predicate["channel"]` (`mirror_chat_channel`) so the previous release
  still matches correctly during the rolling deploy. The API, MCP and the
  serializer never show it. Removing it is the contract step (§15.1).
- **Direct chats.** A Teams 1:1 chat starts no trigger, and the trigger form's
  "Anywhere" and "Direct messages" choices are gone. `help`, `/run` and `/status`
  still answer there. Slack "Direct messages" triggers, which could never fire
  (G12), are switched off by the migration.
- **Tools.** A refused target's error lists the company's connected channels by
  name. Nothing is added to the run context.
- **The bot's name.** Slack's is stored in the install's `settings["bot_name"]`
  from `auth.test`: at install, or on the first code asked for when the install
  predates this. Teams' is `Teams::AppPackage::NAME`.
- **Not in phase 1.** The message ledger (§11.2) is not built yet, because
  until channels are shared every bot message in a channel is the same company's.
- **Migration** (`20261022100100_connect_existing_chat_channels`).
  - Channels are read from trigger conditions, chat events (the last 90 days,
    and every event a trigger fired on), run origins (90 days) and step and
    sub-step instructions.
  - Every Teams channel and group chat already in the registry is connected.
  - Copies of a split trigger are named `<name> (2)`, `<name> (3)`.
  - It logs counts only.

## 21. Phase 2 as built

On the same branch as phase 1. Where it differs from the sections above:

- **The token stays on each company's install.** `chat_workspaces` holds no
  credentials. Each company's `Integration` keeps its copy of the bot token, and
  `Slack::IntegrationService` hands the latest one to every install of the
  workspace on each install or reinstall. That reinstall also switches back on
  the installs an uninstall had switched off. Every reader of
  `credentials_data["bot_token"]` therefore works unchanged, and spike S1 stops
  mattering: whichever token Slack returns last serves everyone.
- **Linking to the workspace.** `Integration#attach_chat_workspace` links an
  install to its workspace from `team_id` / `tenant_id`; the migration links
  existing installs the same way. `Integration#chat_peers` is the installs of
  every company on that workspace.
- **The registry.** It is looked up by workspace (`ChatConversation.in_workspace_of`).
  `integration_id` stays as the install that first recorded a row, now nullable
  with `on_delete: :nullify`, so a company's disconnect leaves the shared rows in
  place. An install that serves no workspace yet keeps a registry of its own.
- **The endpoint.** One endpoint per workspace keeps hearing through the install
  it names (`WebhookEndpoint#chat_install`). That install falls back to another
  company's when it is inactive, and when it is removed the endpoint is handed to
  a peer (`Integration#hand_endpoints_to`). It is disabled (Slack) or deleted
  (Teams) only when the last company leaves.
- **The router.** `Chat::WorkspaceRouter` runs from `ProcessEventJob` for every
  chat endpoint. A message no company's trigger matches is stored in no company
  and gets the help catalog once.
- **The ledger.** `chat_messages` records what `chat_post_message`, status cards
  and connect confirmations post, per company. `chat_update_message` /
  `chat_delete_message` check it only in a channel connected to two or more
  companies; elsewhere every bot message is the one company's.
- **Rate limits.** `Slack::Client::RateLimited` carries `retry_after`. The tools
  answer `rate_limited`, the way Teams' 429 already did. `Slack::Notifier` raises
  it only for an agent's call (`raise_rate_limit: true`); system posts keep
  logging and moving on.
- **Self-service.** `Chat::RunCatalog` spans the person's companies on the
  workspace, naming the company when there is more than one. `Chat::RunStarter`
  records the run under the company of the chosen project, through that
  company's install. Linking an account accepts a member of any of those
  companies. The link page names only the person's own companies (decision 17).
- **Confirmation link.** Slack's comes from `chat.getPermalink`, which needs no
  scope. Teams' is the message the code was posted in, whose thread holds the
  confirmation. It is stored as `confirmation_url` and shown on the Channels list.
- **Spike S2.** `Chat::TeamsProvider.normalize` now keys a channel message by
  `channelData.channel.id`, as `ChatConversation.record_teams!` always did. S3
  and S4 still want a live check on staging.

## Sources

- Code at `715fc7c0`:
  - `app/controllers/webhooks/{slack,teams}_controller.rb`
  - `app/jobs/webhooks/process_event_job.rb`
  - `app/services/trigger_engine.rb`
  - `app/models/{trigger_binding,integration,chat_conversation,chat_identity,webhook_endpoint}.rb`
  - `app/services/chat/`, `app/services/slack/`, `app/services/teams/`
  - `app/services/internal_tools/chat_*.rb` and `concerns/{chat,slack}_context.rb`
  - `app/services/templates/{exporter,installer,setup_checklist}.rb`
  - `app/services/project_move/`
  - `app/frontend/shared/resources/triggers/TriggerFormPanel.tsx`
- Production data: read-only queries, 2026-10-21 and 2026-10-22 (§4).
- [teams-integration.md](./teams-integration.md) §6–§9, §19–§21;
  [technical-slack-multi-tenant-workspace-routing-design-2026-06-28.md](../research/technical-slack-multi-tenant-workspace-routing-design-2026-06-28.md).
