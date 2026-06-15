# Configuration

How Aixle Flow is configured at three different levels.

## 1. Environment variables — host-level

Stored in `.env.development` (or `.env.production`). These configure
the Rails app itself: database, Redis, OAuth provider credentials, Git
host integrations.

See the Configuration reference page for the complete list of supported
variables.

## 2. Config Items — company / project level

Inside the app, **Config Items** (the **Secrets & Variables** section)
are encrypted at rest and injected into:

- MCP server `headers` / `env`
- Agent runtime environment
- Custom Tool execution

This is where you put things like a third-party API key that an MCP
server needs to call. **Never** put these in `.env` files — they belong
in Config Items so they live with the project, not the deployment.

## 3. Per-user — Profile

Each user keeps their own:

- Agent runtime credentials (Claude API key, OpenAI key, etc.).
- Default LLM model.
- Onboarding state.

These are scoped to the user, encrypted, and never visible to other
team members.

## Decision table

| You want to configure…                | Where it goes                          |
| ------------------------------------- | -------------------------------------- |
| Database / Redis / Temporal           | `.env.development`                     |
| Google OAuth / GitHub App credentials | `.env.development` (host)              |
| GitHub App private key                | `.env.development` (host)              |
| GitLab / Linear access token          | **Company → Integrations** (in-app)    |
| Anthropic / OpenAI / etc. API keys    | **Profile → Agent Credentials** (per-user) |
| Third-party API key for an MCP server | **Config Items** (project or company)  |
| Project-specific URL or feature flag  | **Config Items**                       |
| LLM model preference                  | **Profile**, or `preferred_model` on a Step |
