# YouTrack integration

Connect a permanent-token identity to one YouTrack project from a project's **Integrations** page. The token owner needs read access to the project, issues, fields, comments and users, plus permission to add comments, update issue fields and manage tags. A dedicated automation account is recommended.

After connecting, install/enable JetBrains' **Webhook Triggers** app for the selected project and configure **All Events** manually:

1. Copy the callback URL shown on the integration card.
2. Use the displayed header name (`X-YouTrack-Token` by default).
3. Enter the same project-wide webhook token used while connecting (at least 32 characters).

Delivery is best-effort. Aixle accepts only issue-created events and new comments that mention the connected account. Unsupported, forged, project-mismatched, and unmatched bodies are not retained. Disconnecting disables new webhook runs and tool calls, while existing task links remain available.

The integration exposes seven workflow tools for searching and reading issues/comments, adding comments, updating issues, managing tags, and listing project users. Every operation is restricted to the selected YouTrack project.

Company administrators can select company scope to share a connection across projects; project connections remain local to that project. Each workflow trigger selects an active connection and supports text matching and the standard Subject controls. `create_task` creates a separate task and external link for each matching workflow. `existing_task` prefers the oldest active link for that workflow, otherwise uses the sole active task in the project. Ambiguous matches start without a task and log `ambiguous_external_subject`.

To rotate a webhook token, use the connection's webhook settings to change its token and, if necessary, header name, then update the YouTrack app to the same values. The app shares one token across its project's callback URLs, so coordinate the change with other consumers. Rotation updates the endpoint's encrypted secret; the integration does not keep a second copy. Requests using the old token fail immediately.

For delivery troubleshooting, inspect `last_received_at` on the connection and ordinary webhook/trigger logs. Check the callback URL, header and token, selected project, enabled trigger and text filter. Only the two supported events can start runs; editing a comment or mentioning the account in an issue description does not. Callback payloads and run context contain bounded excerpts; agents use the tools for full current content. Accepted records follow the normal webhook, trigger, dispatch and run retention policies.

Outbound requests require HTTPS, validated destinations and TLS verification, with response-size and timeout limits. Redirects are rejected; configure the final instance URL, retaining any self-hosted path. Operators can use the deployment's shared `url_safety.trusted_hosts` setting for an intentionally trusted private host; this does not disable TLS, size or timeout checks. Runtime authentication failures return sanitized tool errors. Reconnect after replacing credentials; task links survive when the normalized instance URL stays the same. Instance-domain changes and moved or renamed YouTrack projects are unsupported.

A dedicated automation identity may consume a YouTrack license seat and affect notifications. Configuring the Webhook Triggers app requires Update Project separately from the runtime token's permissions. The integration never posts automatic progress or completion comments; agent writes depend on workflow instructions.
