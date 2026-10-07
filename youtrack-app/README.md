# Aixle Flow — YouTrack app

The YouTrack side of Aixle's YouTrack tracker. It is published on the public JetBrains
Marketplace as **Aixle Flow** (vendor: Dualboot Partners) and is the only way a YouTrack instance
connects to Aixle: a YouTrack admin installs it, and Connect provisions everything else. Design:
[`docs/design/task-tracker-integrations.md`](../docs/design/task-tracker-integrations.md) §12,
phase 5.

Requires YouTrack 2026.2 or later.

## What it does

- **Connect.** Creates (or reuses) the password-less service user `aixle-flow` ("Aixle Flow")
  through Hub, adds it to the chosen projects' teams, attaches the app to them, mints the user's
  permanent token, and hands the token to Aixle. Aixle never sees an admin credential.
- **Events.** An on-change rule posts issue created, State, Assignee and comment events to the
  project's events URL with the project's secret.

## Layout

| Path | What |
|---|---|
| `manifest.json` | name `aixle-flow`, title "Aixle Flow", widgets |
| `settings.json` | `flowUrl` (global); `eventsUrl`, `secret`, `statusField`, `assigneeField` (per project) |
| `aixle-flow-events.js` | the on-change rule |
| `widgets/connect/` | `ADMINISTRATION_MENU_ITEM` (Administration → Integrations › Aixle Flow): status, consent, project choice, `flowUrl` |
| `widgets/setup/` | `DASHBOARD_WIDGET`: the provisioning, which needs `host.fetchHub` — only dashboard widgets have it. `config-schema.json` declares its one config key, `handover` |
| `icon.svg` | 40×40 Marketplace icon |
| `bin/package` | builds `dist/aixle-flow-<version>.zip` |

No build step: plain JavaScript, loaded by the widget HTML as is. Both widgets require the
`ADMIN_UPDATE_APP` permission (Low-level Admin Write), so only administrators see them.

## Protocol with Aixle

`flowUrl` is the Aixle deployment the app talks to: a global setting, default
`https://flow.aixle.com`. The app never takes an Aixle URL from a link — a link that named the
Aixle to talk to would let anyone collect a service-user token.

### Pairing

A pairing is a 15-minute, single-use handshake identified by `id` and authenticated by `secret`
(sent as `Authorization: Bearer <secret>`). Aixle's public pairing endpoints answer CORS for any
origin without credentials: a widget's origin is `null`.

**Started in Aixle.** The user presses Connect YouTrack on a project's Trackers page and enters the
instance URL. Aixle creates a pairing bound to that project and user and sends the browser to

```
<instance>/admin/app/aixle-flow/connect#app_pairing=<id>.<secret>
```

YouTrack hands an app only the URL parameters prefixed `app_`: the page reads `pairing=…` from
its app location, and a plain `#pairing=` never reaches it. The page then removes the fragment
from the address bar. `?app_pairing=` works too, but a fragment keeps the secret out of server
logs.

**Started in YouTrack.** The connect page calls

```
POST {flowUrl}/integrations/youtrack/pairings
{ "instance_url": "https://acme.youtrack.cloud" }
→ 201 { "id", "secret", "code": "ABCD-2345", "approve_url", "expires_at" }
```

shows `code` ("Enter this code in Aixle Flow"), opens `approve_url` in a popup and polls
`GET …/pairings/:id` until `status` is `approved`. `approve_url` is Aixle's generic
`{flowUrl}/integrations/youtrack/connect` page and carries nothing about the pairing: the user
signs in, **types the code**, picks the project and approves — the device-authorization pattern
(RFC 8628), so a link someone else sends cannot attach their YouTrack to your project.

### Reading a pairing

```
GET {flowUrl}/integrations/youtrack/pairings/:id
Authorization: Bearer <secret>
→ 200 {
  "status": "pending" | "approved" | "completed" | "expired",
  "instance_url": "https://acme.youtrack.cloud",
  "code": "ABCD-2345",
  "company": { "name": "Acme" } | null,
  "project": { "name": "Support" } | null,
  "approved_by": { "name": "Jane Doe" } | null
}
```

The connect page must show `company.name` and `project.name` prominently before the admin
approves: that screen is the consent. It also refuses a pairing whose `instance_url` is not the
instance it runs in, or whose status is not `approved` (it keeps polling a `pending` one).

### Hand-over to the setup widget

Only dashboard widgets can call Hub, so on Approve the connect page creates — or updates in place —
the admin's private dashboard "Aixle Flow setup" (`POST /api/dashboards`) with the setup widget,
whose config `handover` carries the pairing id and secret and the chosen project ids, and sends
the browser to `<instance>/dashboard?id=<id>`. The widget runs without input and clears
`handover` as soon as `complete` has succeeded; every step is safe to repeat, so a failed setup
offers Retry.

YouTrack asks the admin to allow each request an app makes that changes data ("The Aixle Flow app
is attempting to make a POST request to the … endpoint"): one for the dashboard, then about
up to 2 + 3 per project during setup unless the admin picks "Allow and don't ask again". A denied request
stops the step with a clear message.

### Completing a pairing

After provisioning, the setup widget calls

```
POST {flowUrl}/integrations/youtrack/pairings/:id/complete
Authorization: Bearer <secret>
{
  "app_version": "1.0.0",
  "instance_url": "https://acme.youtrack.cloud",
  "token": "perm-…",
  "service_user": { "id": "2-7", "login": "aixle-flow" },
  "projects": [ { "id": "0-1", "key": "APP", "name": "Application" } ]
}
→ 200 {
  "projects": [
    { "id": "0-1", "events_url": "https://…/webhooks/trackers/<token>", "secret": "…",
      "status_field": "State", "assignee_field": "Assignee" }
  ],
  "return_url": "https://flow.aixle.com/company/projects/12/trackers"
}
→ 4xx { "error": "<code>", "message": "<human readable>" }
```

Aixle verifies the token against `instance_url` (`/api/users/me` must be `service_user`, every
project must be visible to it) before it stores anything. The widget then writes each project's
`eventsUrl`, `secret`, `statusField` and `assigneeField` into that project's app settings and
offers a button to `return_url` (only when it is on `flowUrl`'s origin). If `complete` answers an
error, the widget revokes the token it minted.

The token is named `Aixle Flow — <company> / <project>` and is scoped to YouTrack and Hub, so Aixle
can revoke it with the token itself on disconnect: `GET /hub/api/rest/users/me/permanenttokens?fields=id,name`,
then `DELETE /hub/api/rest/users/me/permanenttokens/<id>`. YouTrack keeps accepting a revoked token
for up to about 20 seconds.

### Events

The rule posts to the project's `eventsUrl`:

```
POST <eventsUrl>
Content-Type: application/json
X-Aixle-Token: <secret>
{
  "version": 1,
  "event": "issue_created" | "issue_updated" | "comment_added",
  "issue": "APP-123",
  "project": "APP",
  "actor": "jane",
  "at": 1791350199000,
  "changes": {
    "status":   { "from": "Open", "to": "Ready for AI" },
    "assignee": { "from": null, "to": "jane" }
  },
  "comments": [ { "id": "7-4", "author": "jane", "created": 1791350199000 } ]
}
```

`changes` carries only the fields that changed; `comments` only for `comment_added`. `from` and
`to` are a state's or value's name and a user's login, an array of them for a multi-value field,
or `null`. One change that touches State or Assignee and adds a comment sends `issue_updated`, then
`comment_added`. Aixle treats every event as a notification and re-reads the issue, the change and
the comment through the API before anything fires. Comment text is never sent.

Events leave after the change is committed: a rule may schedule only one async call per
execution, so the rule chains them. Comments are read after the commit, so `created` is the
stored creation time (inside the transaction it is up to a few hundred milliseconds earlier).
The scripting API has no comment id; the rule takes it from the comment's URL
(`…#focus=Comments-7-4.0-0`), so `id` is `null` if YouTrack ever changes that format, and Aixle
then finds the comment by author and `created`.

`version` lets Aixle accept older app versions: YouTrack does not update installed apps by itself.

## Developing

Releases go through JetBrains' manual review (3–4 working days per version), so iterate against a
YouTrack instance of our own: `bin/package`, then upload the ZIP
(`POST /api/admin/apps/import`, multipart field `file`) with an admin permanent token, and set
`flowUrl` to the Aixle you test against. Customers only ever get the Marketplace build.

`flowUrl` must be an address the admin's browser may call from the YouTrack page. Chrome's Local
Network Access blocks a page on a public YouTrack (Cloud) from calling `localhost` or a private
address, and the widget iframe cannot be granted that permission, so a local Aixle needs a public
tunnel or a self-hosted YouTrack on the same network. `http://` is accepted only for `localhost`.

The rule logs to the app's log (`GET /api/admin/apps/<id>/logs`) only when delivery fails. That
log survives reinstalling the app, so never log a secret while debugging.
