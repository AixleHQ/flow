# Connecting Microsoft Teams

Microsoft Teams connects per **company**. One connection serves every project in
the company. From then on:

- people start workflows by mentioning the app in a channel or group chat, or by
  messaging it directly (a **Chat message** trigger);
- the thread a request came from gets a status card that follows the run;
- agents in workflow steps post, edit, delete and read messages with the
  `chat_*` tools, and send and receive files.

Approvals and gates are answered in Flow, not in Teams. The app has no buttons
yet.

---

## Connect your organization

A Teams connection is approved by an administrator of your Microsoft 365
organization, who does not need a Flow account.

1. On a project's **Integrations** page choose **Connect → Microsoft Teams**.
   Any member who can change the project can do this.
2. Flow shows an **approval link**. Copy it and send it to your Microsoft 365
   administrator. The link works for 7 days and is shown only once. If it is
   lost, choose **New approval link** on the waiting row.
3. The administrator opens the link and selects **Sign in with Microsoft to
   approve**. They must hold one of these directory roles: Global
   Administrator, Privileged Role Administrator, Cloud Application
   Administrator, Application Administrator, or Teams Administrator. A sign-in
   without one of them binds nothing.
4. The organization is now connected. The row on the **Integrations** page
   shows its domain and who approved it.

An organization belongs to one company. If another company already connected it,
the approval is refused.

### File access

After approving, the administrator can choose **Grant file access**. That is a
separate Microsoft consent for the permission `Files.ReadWrite.All`. Flow needs
it to read files people attach in channels and group chats, and to save files
into channels. The administrator may decline: everything else works without it,
and the row shows **files off**. They can grant it later from the same approval
link.

Flow uses the permission only for:

- files attached to a message that addressed the app;
- files it saves into the `Aixle` folder of the channel a run answers in.

### Add the app in Teams

The administrator downloads the app package with **Download the Teams app**,
on the approval page or on the row in Flow, and uploads it to the
organization's app catalog in the Teams admin center (**Teams apps → Manage
apps → Upload new app**).

Then people add the app to the teams and group chats where it should listen, or
open it for a 1:1 chat. When the app joins a team, it learns the team's channels
and says hello once. In teams with more than 100 members it stays quiet.

The package asks Teams for two resource-specific permissions, which apply only
to the teams and chats the app is added to:

| Permission | What Flow uses it for |
| --- | --- |
| `ChannelMessage.Read.Group` | Reading a channel thread for `chat_read_thread`, and the files on a message |
| `ChatMessage.Read.Chat` | The same in group chats |

Teams delivers every channel message to an app with these permissions. Flow
drops on arrival every message that does not mention the app, and stores
nothing from it.

---

## Start a workflow from Teams

On the workflow, open **Triggers → Add a trigger**. Under **Trigger type**,
choose **Chat message**, then:

- **Messenger**: **Microsoft Teams**.
- **Where**: **Anywhere the bot is addressed**, **Direct messages**, or one
  channel or group chat. The list shows the channels of every team the app was
  added to, and the group chats it is in.
- **Text match** and **Pattern** limit the trigger to some messages: **contains**,
  **equals**, **regex** or **starts with**. Leave **Pattern** blank to accept
  every message.
- **Cooldown (s)**, **Report back in the thread** and **Subject** work as for
  every chat trigger; see below.

### What counts as addressing the app

- In a channel or group chat, a message must **mention** the app: pick it from
  the `@` list. Typing `@Aixle Flow` as plain text is not a mention, and Teams
  does not tell the app about it.
- In a 1:1 chat with the app, every message counts.

The pattern is matched against the message without the mention, ignoring case.

### Asking what is available: help

Mention the app with `help`. It replies with the triggers that apply to that
conversation, in every project of the company. It also replies this way when a
message matches no trigger. `help` is reserved, so no trigger can use it as a
pattern.

### The status card

With **Report back in the thread** set to **A status card that follows the run**
(the default), the app posts one card in the thread and edits it as the run
moves:

| The run | The card |
| --- | --- |
| Accepted, waiting to start | ⏳ Accepted — the workflow and run number |
| Running | ▶️ Running, since when |
| Completed | ✅ Completed, and how long it took |
| Failed | ❌ Failed, with the failed step and its error |
| Cancelled | ⏹️ Cancelled |
| Not started (cooldown, or a step needs a person) | ⏭️ Not started, and why |

Each card for a run links to it. **Only when a run fails** posts one message on
failure instead, and **Nothing** keeps the thread quiet.

### Who the run belongs to

A Teams-started run belongs to the person who added the trigger, and it uses
their credentials, as with Slack. Anyone in the organization who can address
the app in an accepted conversation can start it. Flow records who asked: it is
shown on the run page, and an agent sees the sender's name. A sender who signs
in to Flow with Microsoft is recognized as that Flow user. Flow never matches
people by email address.

### What the run receives

- **The message**, with the name of the person who sent it.
- **Where to reply**: the channel thread, group chat or 1:1 chat it came from.
- **Attached files**, saved into the project's assets in a `teams` folder and
  passed to the run: up to 10 files of up to 50 MB each. In a 1:1 chat this
  always works. In channels and group chats it needs file access; without it the
  files are left out. Images pasted into a channel or group chat message are
  included even without it.

---

## Tools

| Tool | What it does |
| --- | --- |
| `chat_post_message` | Sends Markdown `text`, an `adaptive_card`, files, or a mix. Returns the message id. `new_thread: true` starts a new thread in the channel. |
| `chat_read_thread` | Reads the latest messages of a channel thread or a group chat, oldest first. In a 1:1 chat Teams gives apps no history, so it returns the message that started the run. |
| `chat_update_message` | Replaces a message the app posted. |
| `chat_delete_message` | Deletes a message the app posted. |

The same tools work in Slack, and they answer in whichever messenger the run
came from. In a run that started from Teams, the conversation and thread default
to the triggering message. Elsewhere, pass `provider: "teams"` and a
`conversation`: `Team/Channel`, a channel name, or its id.

- **Adaptive Cards** up to version 1.5. Cards with `Action.Submit` or
  `Action.Execute` are refused, because nothing receives their clicks yet;
  `Action.OpenUrl` works.
- **Throttling.** When Teams throttles the app, the tool returns `rate_limited`
  with when to retry, rather than waiting.

### Sending files

| Where | How the files arrive |
| --- | --- |
| Channel, with file access | Saved into the channel's files, in an `Aixle` folder, and linked in the thread |
| 1:1 chat | Teams asks the person to accept the file, then saves it in their OneDrive |
| Group chat, or a channel without file access | Saved as project assets in Flow, and linked from the chat |

---

## Disconnecting

**Remove** on the Integrations row (company admins only) disconnects the
organization. The app stays installed in Teams until an administrator removes
it there, but Flow no longer acts on its messages. Triggers stay in Flow;
nothing reaches them. Another company can then connect the organization.

If someone mentions the app from an organization that is not connected, it
answers at most once a day per conversation that the organization has not
connected Flow yet.

---

## Self-hosted: the Teams app

The operator registers one bot for the whole deployment. Every customer
organization uses that same bot.

1. **Microsoft Entra app registration** (in the operator's own tenant):
   - Supported account types: accounts in any organizational directory
     (multitenant). No personal Microsoft accounts.
   - A certificate credential. Flow signs in with it. A client secret is for
     development only.
   - Redirect URIs (Web):
     `<PROTOCOL>://<DOMAIN>/integrations/teams/callback` and
     `<PROTOCOL>://<DOMAIN>/integrations/teams/file_access/callback`.
   - **Token configuration → Add groups claim → Directory roles**, so the
     administrator's sign-in carries their roles (`wids`). Without it, every
     approval is refused.
   - **API permissions**: add the Microsoft Graph application permission
     `Files.ReadWrite.All`. Do not grant admin consent for your own tenant
     unless your own organization will connect too. Each customer's
     administrator grants it for their organization.
2. **Azure Bot** resource, in a subscription of the same tenant:
   - Type: single tenant, using the app registration above.
   - Messaging endpoint: `https://<DOMAIN>/webhooks/teams/activities`.
   - Channels: add **Microsoft Teams**.
3. Configure the deployment:

   ```bash
   TEAMS_APP_ID=<application (client) id>
   TEAMS_HOME_TENANT_ID=<the tenant id of the app registration>
   TEAMS_PRIVATE_KEY=<the certificate's private key, PEM>
   TEAMS_CERT_THUMBPRINT=<the certificate's SHA-1 thumbprint, hex>
   ```

   When Microsoft sign-in already uses the same app registration, Flow falls
   back to `MICROSOFT_CLIENT_ID`, `MICROSOFT_PRIVATE_KEY` and
   `MICROSOFT_CERT_THUMBPRINT`; then only `TEAMS_HOME_TENANT_ID` is needed.

Until the app id, the home tenant and a credential are set, projects are not
offered Microsoft Teams. `TEAMS_ALLOWED_TENANT_IDS` (comma-separated) limits
which organizations may connect, for example to your own.

The app package is built by Flow for the deployment's own bot, so there is
nothing else to edit. Raise `Teams::AppPackage::VERSION` when the manifest
changes, so organizations can tell their installed package is older.
