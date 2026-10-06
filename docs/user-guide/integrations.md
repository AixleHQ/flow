# Integrations

An integration is a connection from a Flow project to an outside service. It
is what lets agents clone and push code, read and change issues, post to chat,
or run on remote machines, and it is what lets events in those services start
workflows. Connect them from the project's **Integrations** page.

Each integration has its own page:

| Integration | What it gives a project | Page |
| --- | --- | --- |
| **GitHub** | Repositories cloned in sessions with `git` and `gh` authenticated, CI gates on checks and workflow runs, GitHub Projects as trackers | [GitHub](/docs/github) |
| **GitLab** | Repositories cloned in sessions, CI gates on pipelines | [GitLab](/docs/gitlab) |
| **Azure DevOps** | Repositories and pull requests, Azure Boards as a tracker, Service Hooks | [Azure DevOps](/docs/azure-devops) |
| **Jira** | Jira Cloud projects as trackers: tracker triggers and the `tracker_*` tools | [Jira](/docs/jira) |
| **Linear** | Linear teams as trackers: tracker triggers and the `tracker_*` tools | [Linear](/docs/linear) |
| **YouTrack** | YouTrack projects, Cloud or self-hosted, as trackers: tracker triggers and the `tracker_*` tools | [YouTrack](/docs/youtrack) |
| **Slack** | Workflows started by mentioning the app, replies and failure notices in the thread, the `slack_*` tools | [Slack](/docs/slack) |
| **Coder** | Remote workspaces an agent can allocate, run commands on and release | [Coder](/docs/coder) |

Azure Boards, Jira, GitHub Projects, Linear and YouTrack are all **trackers**. What a
tracker is, the project's **Trackers** page, the one-column intake and tracker
triggers are described once, on [Trackers](/docs/trackers).

Two things look like integrations but live elsewhere:

- **Sign-in with Google or Microsoft** is configured by whoever runs the
  installation: [Configuring sign-in methods](/docs/configuring-sso).
- **Tools from other services** (Notion, Sentry and the like) come from MCP
  servers, added on the project's **Connectors** page:
  [MCP servers](/docs/mcp). Linear's own MCP server is one too, apart from the
  Linear tracker.

## Webhooks reference

The endpoints outside services call. All of them are public (no session) and
each verifies the caller its own way.

| Source | Endpoint | Verified by |
| --- | --- | --- |
| GitHub | `POST /webhooks/github` (CI gates and GitHub Projects trackers) | HMAC signature with `GITHUB_WEBHOOK_SECRET` |
| GitLab | `POST /webhooks/gitlab` | A secret per repository hook |
| Azure DevOps | `POST /webhooks/azure_devops/<endpoint id>` | HTTP Basic, one password per subscription |
| Jira | `POST /webhooks/trackers/<endpoint token>`, or `POST /webhooks/trackers/app/jira` for the Atlassian app | HMAC signature per subscription; the app's signed JWT |
| Linear | `POST /webhooks/trackers/<endpoint token>` for an API-key connection, or `POST /webhooks/trackers/app/linear` for the Linear app | `Linear-Signature` HMAC with the subscription's secret, or with `LINEAR_WEBHOOK_SECRET`, and a timestamp within a minute |
| YouTrack | `POST /webhooks/trackers/<endpoint token>`, one per connected YouTrack project | The token the project's Webhook Triggers app sends, in the header it is set to send it in (`X-YouTrack-Token` by default) |
| Slack | `POST /webhooks/slack/events` | Slack's request signature with `SLACK_SIGNING_SECRET` |
| Incoming webhook trigger | `POST /webhooks/in/<slug>` | What the trigger is set to: HMAC SHA-256, a shared token header, or nothing |

Azure DevOps sends no signature, so the subscription's own password is the
whole credential. That is why the endpoint id in its URL is only a route, never
a secret.
