# YouTrack integration

Connect a permanent-token identity to one YouTrack project from a project's **Integrations** page. The token owner needs read access to the project, issues, fields, comments and users, plus permission to add comments, update issue fields and manage tags. A dedicated automation account is recommended.

After connecting, install/enable JetBrains' **Webhook Triggers** app for the selected project and configure **All Events** manually:

1. Copy the callback URL shown on the integration card.
2. Use the displayed header name (`X-YouTrack-Token` by default).
3. Enter the same project-wide webhook token used while connecting (at least 32 characters).

Delivery is best-effort. Aixle accepts only issue-created events and new comments that mention the connected account. Unsupported, forged, project-mismatched, and unmatched bodies are not retained. Disconnecting disables new webhook runs and tool calls, while existing task links remain available.

The integration exposes seven workflow tools for searching and reading issues/comments, adding comments, updating issues, managing tags, and listing project users. Every operation is restricted to the selected YouTrack project.
