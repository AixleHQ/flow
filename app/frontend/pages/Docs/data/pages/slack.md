# Connecting Slack

Slack connects per **company**. When you connect a Slack workspace, the install
belongs to the company and serves every project in it. From then on:

- an @mention of the app in a connected channel can start a workflow (a **Chat
  message** trigger for Slack);
- the thread a request came from gets a status card that follows the run;
- agents in workflow steps post, edit, delete and read messages with the
  `chat_*` tools.

Flow has no slash commands and no buttons in Slack, so approvals and gates are
answered in Flow, not in Slack.

Any member who can change a project connects Slack from that project's
**Integrations** page; viewers cannot. Because the install is company-wide, it
shows on every project's Integrations page with the scope **company**, and only
a company admin can remove it.

---

## Connect a workspace

1. On a project's **Integrations** page choose **Connect → Slack**. On an empty
   page, the **Slack** button does the same.
2. Slack shows its consent screen. Pick the workspace and approve the
   permissions listed below.
3. You return to Flow with *"Slack connected to &lt;workspace&gt;"*. The new row
   is named after the workspace, with provider **Slack** and scope **company**.

**Slack** is offered only on a deployment that has a Slack app (see
[Self-hosted: the Slack app](#self-hosted-the-slack-app)).

Finish within ten minutes, signed in to Flow as the same person who started.
Otherwise the authorization is refused and you start again.

Then connect the channels Flow may use: see [Connect a channel](#connect-a-channel).

### What the app asks for

| Scope | What Flow uses it for |
| --- | --- |
| `app_mentions:read` | Receiving the @mentions that start workflows |
| `chat:write` | Replies, the `/help` list, status cards, and posting, editing and deleting messages |
| `channels:history`, `groups:history` | `chat_read_thread` in public and private channels |
| `channels:read`, `groups:read` | Showing the name of a connected channel |
| `files:read` | Downloading files attached to a mention, so the run gets them |
| `files:write` | Attaching files with `chat_post_message` |
| `commands` | The **Run workflow** shortcut and the slash command |

The app asks for no direct-message history, so threads in DMs cannot be read.

### More than one workspace

A company can connect several workspaces: each one gets its own row.

Several companies can also connect the same workspace. Each one reaches only the
channels connected to it: another company's channels never show up for you, and
messages there never reach your triggers. A channel connected to more than one
company starts the matching triggers of each, and the app answers `/help` once,
naming every company that listens there. The app is the same bot for everyone,
so a company's agents edit and delete only the messages posted for that company.

Connecting the same workspace again, from any project, refreshes its token on the
existing row. Your triggers stay as they are.

---

## Connect a channel

Flow reaches only the channels connected to your company. A trigger listens in
one of them, and agents post, read and edit only there (and in the thread a run
came from). A channel is never typed in by its ID: it is connected from inside
the channel, by someone who is in it.

1. Ask for a code in Flow, in one of two places:
   - in a chat trigger, next to **Channel**: **Connect a new channel…**;
   - on the Slack row of the **Integrations** page: **Connect a channel**, for a
     channel that workflows only post to, such as one for reports.
2. Invite the app to the channel if it is not there yet: `/invite @<app>`. The
   dialog shows the app's name.
3. In the channel, type `@<app>`, pick the app from the list, and paste the
   rest of the line the dialog shows: `connect aixle-7F3K9QXM`.
4. The app answers in the thread, for everyone in the channel to see: which
   company the channel is now connected to, who asked for the code and who
   posted it, and, when the code came from a trigger, that the trigger listens
   there. The dialog in Flow shows the channel as connected.

A code works once, for ten minutes. Anyone who can change a project can ask for
one. Whoever posts it must be in the channel, which is what makes the
connection the channel's own choice; a code passed on to someone in the channel
works too, and the app's answer stays in the channel as the record.

A connection belongs to the company, so every project in it can use the
channel. It stays when the person who posted the code leaves the channel.

Each connected channel on the Slack row links to the app's confirmation in
Slack (**View in Slack**). To disconnect a channel, choose **Disconnect** next
to it. The app says in the channel that your company disconnected it. Triggers that
listened there switch off and need a new channel. Removing the app from the
channel (`/remove @<app>`) stops it for everyone, as with any Slack app.

---

## Start a workflow from a Slack message

On the workflow, open **Triggers → Add a trigger**. Under **Trigger type**,
choose **Chat message**, set **Messenger** to **Slack**, and fill in:

- **Channel** is the one channel the trigger listens in. Pick one of the
  channels connected to your company, or choose **Connect a new channel…** (see
  [Connect a channel](#connect-a-channel)). A trigger without a channel cannot
  be switched on and shows **Needs a channel**.
- **Text match** and **Pattern** limit the trigger to some messages. The match
  options are **contains**, **equals**, **regex** and **starts with**. Leave
  **Pattern** blank to accept every mention.
- **Cooldown (s)** is the shortest gap between two runs of this trigger. A
  mention that matches during the cooldown starts nothing. It is `0` by
  default: every matching mention starts a run.
- **Report back in the thread** is **A status card that follows the run** by
  default. See [The status card](#the-status-card).
- **Subject (what the run is about)** decides whether the run gets a card:
  **None — project-level run**, or **Create a task**. With **Create a task**,
  you also pick a **Task column** and can set a **Task title template**.

Select **Add trigger**. Then, in the trigger's channel, mention the app:
`@<app> ship it`. To listen in several channels, add a trigger for each.

A Slack trigger needs a connected workspace. Until the company has an active
Slack install, Flow refuses to add a Slack trigger, or to switch one on, with
*"Slack is not connected for this company…"*. You can still add one switched
off and turn it on after connecting.

### What the pattern is matched against

Only messages that @mention the app are matched. Flow ignores plain channel
messages, reactions and mentions written by other bots.

The pattern is matched against what was typed after the mention, and case
does not matter. Slack sends `@Flow Ship it` as `<@U0ABC123> Ship it`; Flow
drops that leading mention of the app and the spaces around the rest, then
matches `Ship it`. So **equals** `ship it` and **starts with** `ship` both
match it.

- Only a leading mention of the app is dropped. A message that starts with
  someone else's mention keeps it, written as their user ID: `<@U0ABC123>`.
- Slack escapes `&`, `<` and `>` in message text. They are matched as the
  characters you typed.
- **regex** ignores case too. Start the pattern with `(?-i)` to make it
  case-sensitive.

### Who the run belongs to

A Slack-started run belongs to the person who added the trigger, shown as
**Runs as** on the trigger, and it uses their credentials. Flow does not check
who wrote the Slack message. Anyone who can mention the app in an accepted
channel can start the run.

Off-board triggers run unattended. That means a trigger can only be enabled
when every step of the workflow has auto-run switched on.

### Starting a workflow yourself: Run workflow and the slash command

These start a workflow as **you**, without a trigger:

- **Run workflow** on any message: open the message's **⋯** menu → **Run
  workflow** (Aixle Flow). Pick a workflow, add notes if you like, and **Run**.
  The message's text (and your notes) is the request, and the status card
  follows the run in that message's thread.
- **`/aixle run`** (the command name is the one your Slack app registers): the
  same window. The run gets a thread of its own in the channel, opened by a
  line saying who started which workflow.
- **`/aixle status`** lists, only to you, the last ten runs started from that
  channel in the past 30 days, from projects you can open in Flow.

The list holds the workflows of the connected company you may start in Flow
(projects where you can start runs), and only those whose every step may run
unattended. The run belongs to you and uses your credentials, and its status
card says who started it. The app has to be in the channel for its status card.

The first time, the app asks you to **link your Aixle account**: the link opens
Flow, where you are signed in, and asks you to **Sign in with Slack** as the
account you use in that workspace. The link expires after an hour, works only
for the Slack account it was sent to, and does not add a way to sign in to
Flow.

### One mention, every project

One workspace serves every project in the company, by design. So a mention is
matched against the Slack triggers of all those projects that listen in that
channel, and it can start one run in each project that matches. To keep projects
apart, give their triggers different channels.

Slack's own retries of one message never start a second run. To limit how
often people can start one, set the trigger's **Cooldown (s)**.

### What the run receives

- **The message.** The agent's context includes the triggering message as
  Slack sent it, mention included, with its author's Slack ID, and tells the
  agent to treat it as the request.
- **Where to reply.** Flow records the channel and thread for the whole run.
  The `chat_*` tools reply there by default. A top-level mention gets its
  replies in a new thread under it.
- **Attached files.** Files on the mentioning message are saved into the
  project's assets, in a `slack` folder, and passed to the run as input. Flow
  takes the first 10 files and skips any file over 50 MB.
- **A card**, if the trigger creates one. The title template accepts
  `{{date}}` and the event's fields, such as `{{text}}` (the message without
  the mention), `{{user}}` and `{{channel}}`. The default is
  `chat.message — {{date}}`.

### Asking what is available: /help

Mention the app with `/help` and nothing else: `@<app> /help`. The app replies
in the thread with the triggers that listen in that channel, in every project of
the company. Each entry shows its pattern, its workflow and its project.

The app sends the same reply when a mention matches no trigger. If no trigger
listens in the channel at all, it replies *"No Slack triggers configured for this
channel."*

`help` and `connect` are reserved, so a trigger cannot use them as a pattern.

### The status card

With **Report back in the thread** set to **A status card that follows the
run**, the app posts one message in the thread that started the run and edits it
as the run moves: accepted, running since when, then completed (and how long it
took), failed (with the failed step and its error, or that the agent ran out of
credits), or cancelled. A request that started nothing, for example during the
cooldown, gets a card saying why. Each card for a run links to it.

**Only when a run fails** posts a single message when the run fails:

> :x: **&lt;Workflow&gt;** run #&lt;id&gt; failed.
> &gt; &lt;the failed step and its error, or that the agent ran out of credits&gt;
> &lt;link to the run&gt;

**Nothing** keeps the thread quiet. Triggers that reported failures before the
status card existed were switched to it; choose **Only when a run fails** to go
back to the single message.

A run started again by hand from a Slack-started run reports nothing, because
no trigger asked for it.

---

## Tools

| Tool | What it does |
| --- | --- |
| `chat_post_message` | Sends Markdown `text`, Block Kit `slack_blocks`, files, or any mix of them. Each file comes from inline `content`, a `file_path` in the agent's container, or a project `asset_id`. Returns the message id (its `ts`). `new_thread: true` posts at the top of the channel instead of in the thread. |
| `chat_read_thread` | Reads a thread's parent message and its replies, oldest first: 30 by default, 50 at most. Called with no arguments in a Slack-started run, it reads the thread behind the request. |
| `chat_update_message` | Replaces a message the app posted, found by its id. The whole message is replaced. Files already posted cannot be edited. |
| `chat_delete_message` | Deletes a message the app posted, found by its id. The deletion is permanent. |

The same tools work in Microsoft Teams; in a run that started from Slack they
answer in Slack.

Every workflow step session gets these tools automatically when its company has
an active Slack install. For other sessions, attach them from the tool picker's
**Chat** section. Until Slack or Teams is connected, the tools are hidden.

In a run that started from Slack, the channel and thread default to the
triggering message. Anywhere else nothing is filled in, so the agent passes
`provider: "slack"` and a `conversation`: a connected channel's name
(`#reports`) or ID. The tools refuse a channel that is not connected to your
company, and list the ones that are.

Some details:

- **Markdown.** `text` is Markdown and is sent as a Slack `markdown` block, with
  the text as the notification line.
- **Blocks with files.** Slack cannot attach files to a Block Kit message, so
  blocks and files go out in two parts: the message first, then the files in
  its thread.
- **Interactive blocks.** Flow rejects `actions` and `input` blocks. This
  deployment runs no Slack interactivity endpoint, so a click on them would go
  nowhere.
- **Throttling.** When Slack rate-limits the app, the tool returns
  `rate_limited` with how many seconds to wait (`retry_after`). The limit is
  the app's in that workspace, shared by every company that connected it.
- **Which workspace.** Replies go through the workspace the run came from. If
  that workspace was removed or uninstalled, the tools say Slack is not
  connected rather than post through another one. A run that did not start
  from Slack uses the workspace the company connected first.

---

## Removing or uninstalling

- **Remove** on the Integrations row (company admins only) stops Flow from
  listening to that workspace for your company. Other companies that connected
  it keep working. Removing the row does not uninstall the app from the
  workspace; you do that in Slack. Your channels there are disconnected, and
  your chat triggers that listened there switch off and need a new channel.
- **Uninstalling the app in Slack**, or revoking its tokens, marks the row
  **inactive** for every company that connected the workspace. Flow ignores
  further events from it and hides the tools. **Connect → Slack** again, from
  any of those companies, restores it for all of them.

---

## Self-hosted: the Slack app

The operator registers one Slack app for the whole deployment. Every company
installs that same app into its own workspace.

1. Create an app at [api.slack.com/apps](https://api.slack.com/apps).
2. Under **OAuth & Permissions**:
   - Add the redirect URL
     `<PROTOCOL>://<DOMAIN>/integrations/slack/oauth/callback`. Flow builds the
     URL from `PROTOCOL` and `DOMAIN` and sends it to Slack, so it must match
     exactly.
   - Add the nine bot token scopes listed above.
3. Under **Event Subscriptions**:
   - Turn events on.
   - Set the Request URL to `https://<DOMAIN>/webhooks/slack/events`. Flow
     answers Slack's verification challenge on its own. Each Slack row on the
     **Integrations** page shows this URL, with a copy button.
   - Subscribe to the bot events `app_mention`, `app_uninstalled`,
     `tokens_revoked`, `channel_rename` and `group_rename`. The two lifecycle
     events let Flow see when a workspace removes the app; the rename events keep
     a connected channel's name current.
4. Under **Interactivity & Shortcuts**:
   - Turn interactivity on and set the Request URL to
     `https://<DOMAIN>/webhooks/slack/interactions`.
   - Add a shortcut **On messages**: name **Run workflow**, callback ID
     `run_workflow`.
5. Under **Slash Commands**, create a command (for example `/aixle`) with the
   Request URL `https://<DOMAIN>/webhooks/slack/commands`. Its `run` and
   `status` arguments are the ones Flow answers.
6. To let workspaces other than the app's own install it, turn on public
   distribution under **Manage Distribution**.
7. Copy the app's credentials from **Basic Information** into the deployment:

   ```bash
   SLACK_CLIENT_ID=<client id>
   SLACK_CLIENT_SECRET=<client secret>
   SLACK_SIGNING_SECRET=<signing secret>
   ```

Until `SLACK_CLIENT_ID` and `SLACK_CLIENT_SECRET` are both set, projects are
not offered Slack.

Flow checks every event against `SLACK_SIGNING_SECRET`. If the secret is wrong
or unset, Flow refuses every event and mentions do nothing.

Linking a Slack account uses Sign in with Slack with the same app. It returns
to `<PROTOCOL>://<DOMAIN>/integrations/slack/oauth/callback/link`, below the
redirect URL above, which Slack accepts without registering another.

A workspace that installed the app before the `commands`, `channels:read` and
`groups:read` scopes existed has to install it again (**Connect → Slack**). Until
then the shortcut and the command do not show up there, and connected channels
show their ID instead of their name.

`SLACK_SCOPES` changes the scopes Flow requests. It defaults to the nine above
and accepts commas or spaces. If you drop a scope, the feature that needs it
stops working.

Slack has to reach the Request URL, and nothing in Flow overrides that host.
The links in status cards are built from `PROTOCOL` and `DOMAIN`.

---

## Limits

- Only @mentions, the **Run workflow** shortcut and the slash command start
  anything. Flow does not react to plain messages or reactions.
- Only a leading mention of the app is dropped before matching. See
  [What the pattern is matched against](#what-the-pattern-is-matched-against).
- Thread reading works in public and private channels, not in DMs. Slack
  rate-limits it heavily for newer apps outside its Marketplace, so read a
  thread once rather than polling it.
- Attachments: Flow takes 10 files per message, up to 50 MB each.
- A trigger listens in one channel. Direct messages start no trigger.
- If a company connects several workspaces, a run that did not start from Slack
  always posts through the one connected first. It cannot pick another.

## When something goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| *"Invalid or expired Slack authorization"* | More than ten minutes passed between **Connect** and approving in Slack, or you no longer have access to the project | Start again from **Connect → Slack** |
| *"Slack authorization did not match your session"* | You approved in Slack while signed in to Flow as someone else | Sign in as the person who started, and connect again |
| *"This Slack authorization link was already used"* | The callback page was reloaded or revisited | Start again from **Connect → Slack** |
| *"Slack connection was cancelled"* | You declined on Slack's consent screen | Connect again |
| *"Slack OAuth failed: …"* | Slack refused the token exchange. The rest is Slack's error code, such as `bad_redirect_uri` or `bad_client_secret` | Self-hosted: check `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET` and the redirect URL on the app |
| **Connect** has no **Slack** entry | The deployment has no Slack app | Operator: set `SLACK_CLIENT_ID` and `SLACK_CLIENT_SECRET` |
| The row is **inactive** | The app was uninstalled in Slack, or its tokens were revoked | **Connect → Slack** again |
| A mention gets no reply at all | The row is not active, the app is not in the channel, or (self-hosted) the signing secret or event subscription is wrong | Check the row; invite the app; check step 3 and `SLACK_SIGNING_SECRET` |
| *"No Slack triggers configured for this channel."* | No enabled Slack trigger, in any of the company's projects, listens in this channel | Check the trigger's **Channel** and that it is enabled |
| The app answers *"This code is not valid here or has expired."* | The code was already used, is older than ten minutes, is for Teams, or belongs to a company that has not connected this workspace | Ask for a new code in Flow; the dialog shows why the last attempt was refused |
| The app answers *"Post the code in the channel you want to connect…"* | The code was sent in a direct message | Post it in the channel |
| `@<app> connect …` gets no answer | The app is not in the channel, or the mention was typed as plain text | Invite the app, then type `@` and pick it from the list |
| Saving a trigger fails with *"Chat channel is required…"* | The trigger has no channel and is being switched on | Pick a channel, or connect one with **Connect a new channel…** |
| Saving a trigger fails with *"can't name where a message comes from…"* | Its conditions name `channel` or another place (from the API or MCP) | Set the trigger's channel (`chat_channel_id`) instead |
| The app replies with *"Available commands"* instead of starting a run | The mention matched no pattern | Compare the pattern with what follows the mention. A message that starts with someone else's mention keeps it, so use **contains** for those |
| A matching mention starts nothing and gets no reply | The trigger's **Cooldown (s)** has not passed since its last run | Wait, or lower the cooldown |
| Saving a trigger fails with *"Slack is not connected for this company…"* | The company has no active Slack install | Connect Slack, or reconnect an inactive row, then save again. Or save the trigger switched off |
| Saving a trigger fails with *"can't use help — Aixle answers that word before any trigger"* | `help` and `connect` are reserved | Choose another pattern |
| Saving a trigger fails with *"can't run unattended — enable auto-run on these steps first: …"* | A step needs a person to start it | Turn on auto-run for the steps named |
| The trigger shows *"No creator — this trigger cannot start a run"* | It was added before creators were recorded | Re-create the trigger |
| An agent sees *"Slack is not connected for this project"* | No active install in the company | Connect Slack, or reconnect an inactive row |
| An agent sees *"No channel given. Only a run started from Slack has one to fall back on — pass `conversation` explicitly."* | The session did not start from Slack | Pass a connected channel's name or ID |
| An agent sees *"… is not a Slack channel connected to …"* | The channel is not connected to the company | Connect it: **Integrations → Slack → Connect a channel** |
| An agent sees *"Slack rejected the request: …"* | Slack's own error code, such as `not_in_channel` | Invite the app to the channel |
| A run failed but Slack heard nothing | **Report failures back to Slack** is off, the run was started again by hand, or the install is inactive | Turn the switch on, or check the row |
| Files from the message are missing in the run | Over 50 MB, after the tenth file, or not hosted by Slack | Share them another way, for example as project assets |

See [Triggers & gates](/docs/triggers-and-gates) for how triggers and subjects
work in general, and [Tools](/docs/tools) for attaching tools to steps.
