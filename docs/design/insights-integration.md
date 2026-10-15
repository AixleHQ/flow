# Insights project integration

**Status:** Implemented
**Scope:** Rails and frontend connection lifecycle

## Decision

Insights is an explicit per-project integration. An active `Integration` row with
`provider = 'insights'` is the project's sole opt-in; there is no separate sharing
setting.

Each row belongs to both the project and its company. The model verifies that the
project belongs to that company, and a partial unique database index permits at most
one Insights row per project. Reconnecting updates that row rather than creating a
second connection.

Only the project owner or a company administrator may connect or remove Insights.
Other project writers and viewers cannot perform either operation.

## Credentials and API contract

The connect form accepts one ingest token. `Insights::IntegrationService` stores it in
the Integration `credentials` column through the existing encrypted-credentials API.
The token is never written to `settings` and is not exposed by
`IntegrationResource`; the frontend receives only ordinary integration metadata such
as provider, status, project id, scope and connector identity.

The project integrations endpoint handles the lifecycle:

- `POST /company/projects/:project_id/integrations` with `provider: 'insights'`
  connects or reconnects the project.
- `DELETE /company/projects/:project_id/integrations/:id` removes the project row.

The UI label is **Insights** and the technical provider and Ruby namespace are
`insights` and `Insights`.

## Deliberately absent Rails contours

Rails does not schedule or send usage exports to Insights. There is no Rails collector
configuration, outbound collector client, payload builder, export ledger, exporter,
Temporal workflow/activity, schedule, or project sharing switch.

The internal usage-statistics endpoint and local usage accounting remain independent
of this integration. Runtime capability metadata comes from
`Insights::RuntimeResourceAttributes`, which `UsageStatistics::SessionKey` merges into
every session's resource attributes, and is documented in
`docs/architecture/agent-runtime-registry.md`: only Claude Code, Codex, Gemini CLI and
Kiro CLI receive the fixed business-attribute allowlist, and only while this project's
Insights integration is active. The encrypted ingest token is never included. Rails
still does not implement an exporter or forwarding client.

## Verification

Coverage is intentionally limited to the contract:

- model validation, project lookup, encrypted token storage and project uniqueness;
- service connect/reconnect and per-project isolation;
- controller authorization for project owner/company admin versus ordinary writers;
- resource serialization proving credentials are absent;
- frontend provider label, project route payload and management visibility.
