# DB90 — Comprehensive Project Analysis

## Table of Contents

- [1. Project Purpose](#1-project-purpose)
- [2. Repository Structure](#2-repository-structure)
- [3. Technology Stack](#3-technology-stack)
- [4. Data Collection Strategies](#4-data-collection-strategies)
  - [4.1 AI Gateway (Proxy Mode)](#41-ai-gateway-proxy-mode)
  - [4.2 Telemetry Ingestion (Agent Mode)](#42-telemetry-ingestion-agent-mode)
  - [4.3 Webhooks (Passive Collection)](#43-webhooks-passive-collection)
  - [4.4 Limitations and Gaps](#44-limitations-and-gaps)
- [5. Database Architecture](#5-database-architecture)
  - [5.1 TimescaleDB and Time-Series Design](#51-timescaledb-and-time-series-design)
  - [5.2 Custom Enums](#52-custom-enums)
  - [5.3 Complete Table Reference](#53-complete-table-reference)
- [6. Domain Models](#6-domain-models)
  - [6.1 User and Access Control](#61-user-and-access-control)
  - [6.2 Organization and Multi-Tenancy](#62-organization-and-multi-tenancy)
  - [6.3 Projects and Repositories](#63-projects-and-repositories)
  - [6.4 Tool Events and Analytics](#64-tool-events-and-analytics)
  - [6.5 Connectors and Integrations](#65-connectors-and-integrations)
  - [6.6 Governance and Compliance](#66-governance-and-compliance)
- [7. API Reference](#7-api-reference)
  - [7.1 Authentication and Authorization](#71-authentication-and-authorization)
  - [7.2 API V1 Endpoints](#72-api-v1-endpoints)
  - [7.3 Internal API](#73-internal-api)
  - [7.4 Admin Panel](#74-admin-panel)
- [8. Services Layer](#8-services-layer)
  - [8.1 AI Gateway Services](#81-ai-gateway-services)
  - [8.2 OAuth Providers](#82-oauth-providers)
  - [8.3 Webhook Verification](#83-webhook-verification)
  - [8.4 Data Processing Services](#84-data-processing-services)
- [9. Background Jobs](#9-background-jobs)
- [10. Temporal Workflows](#10-temporal-workflows)
- [11. Infrastructure](#11-infrastructure)
  - [11.1 Docker Services](#111-docker-services)
  - [11.2 CI/CD Pipeline](#112-cicd-pipeline)
  - [11.3 Deployment](#113-deployment)
- [12. Implementation Status](#12-implementation-status)
- [13. Critical Gaps and Recommendations](#13-critical-gaps-and-recommendations)

---

## 1. Project Purpose

DB90 is a **multi-tenant SaaS platform** for tracking and analyzing AI coding tool usage across organizations. It targets engineering managers and platform teams who need visibility into how developers use AI assistants (Cursor, GitHub Copilot, Claude Code, Windsurf, etc.) — capturing token consumption, costs, usage patterns, and potential security risks.

**Core value propositions:**

| Capability | Description |
|---|---|
| Cost Visibility | Track token consumption and dollar spend per user, team, project, and tool |
| AI Gateway | Centralized proxy for AI API calls with shared organization keys |
| Usage Analytics | Dashboards with daily/hourly breakdowns, heatmaps, tool comparisons |
| Risk Scanning | Classify and audit events for sensitive data exposure via Temporal workflows |
| Data Retention | Configurable per-organization retention policies (SOC2, HIPAA compliance labels) |
| Integrations | OAuth connectors for GitHub, GitLab, Bitbucket, Jira, Linear, and AI providers |

---

## 2. Repository Structure

DB90 is organized as a **monorepo** with three main packages:

```
db90-rails/
├── packages/
│   ├── api/                  # Rails 8.1 API-only backend
│   │   ├── app/
│   │   │   ├── controllers/  # 35 controllers (API v1, Internal, Admin)
│   │   │   ├── models/       # 21 ActiveRecord models
│   │   │   ├── services/     # 24 service objects
│   │   │   │   ├── ai/       # AI gateway adapters & correlation
│   │   │   │   ├── oauth/    # OAuth provider implementations
│   │   │   │   ├── webhooks/ # Signature verification
│   │   │   │   └── temporal/ # Temporal client wrapper
│   │   │   ├── policies/     # 10 ActionPolicy authorization policies
│   │   │   ├── serializers/  # Alba JSON serializers
│   │   │   ├── jobs/         # 9 Sidekiq background jobs
│   │   │   ├── mailers/      # Invitation mailer
│   │   │   ├── channels/     # ActionCable WebSocket channels
│   │   │   └── dashboards/   # Administrate admin dashboards
│   │   ├── config/
│   │   ├── db/               # Migrations and SQL schema
│   │   ├── spec/             # RSpec test suite
│   │   └── swagger/          # OpenAPI/Swagger documentation
│   └── web/                  # React 19 + Vite 7 frontend
├── temporal/                 # Temporal.io workflow workers
│   ├── workflows/            # Workflow definitions
│   ├── activities/           # Activity implementations
│   └── workers/              # Worker processes
├── keycloak/                 # Keycloak realm config & themes
├── scripts/                  # Setup & utility scripts
├── architecture/             # Mermaid architecture diagrams
├── .github/workflows/        # GitHub Actions CI/CD
├── docker-compose.yml
└── Makefile
```

---

## 3. Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| Frontend | React 19, Vite 7, TypeScript, Tailwind CSS 4, shadcn/ui, TanStack Query | SPA dashboard |
| Backend | Rails 8.1 (API-only), Ruby 3.4.8 | REST API |
| Serialization | Alba | Fast JSON serialization |
| Authorization | ActionPolicy | Policy-based access control |
| Admin | Administrate | Auto-generated admin panel |
| Database | PostgreSQL 17 + TimescaleDB | Relational + time-series |
| Authentication | Keycloak (OIDC) | SSO, social login |
| Workflows | Temporal.io (Ruby SDK) | Durable event processing pipelines |
| Object Storage | MinIO (S3-compatible) | Encrypted raw event quarantine |
| Cache/Queue | Redis, Solid Queue, Sidekiq | Background jobs, caching |
| API Docs | RSwag (OpenAPI 3.0) | Swagger documentation |
| Testing | RSpec, FactoryBot, WebMock, VCR, SimpleCov | Backend tests |
| CI/CD | GitHub Actions | Lint, test, build, security scan |
| Deployment | Kamal + Docker | Container-based deployment |

---

## 4. Data Collection Strategies

DB90 implements three data ingestion channels. Understanding their capabilities and limitations is critical for evaluating the platform.

### 4.1 AI Gateway (Proxy Mode)

**How it works:** The organization registers API keys for AI providers (OpenAI, Anthropic, Gemini, OpenRouter) as `OrganizationConnector` records. Developers send requests to DB90 instead of directly to the provider. DB90 proxies the request, records the usage, and returns the response.

**Endpoints:**
- `POST /api/v1/organizations/:org_id/ai/:provider/chat`
- `POST /api/v1/organizations/:org_id/ai/:provider/completions`
- `GET /api/v1/organizations/:org_id/ai/:provider/models`

**Supported providers:**
- OpenAI (via `Ai::OpenaiAdapter`)
- Anthropic (via `Ai::AnthropicAdapter`)
- Google Gemini (via `Ai::GeminiAdapter`)
- OpenRouter (via `Ai::OpenrouterAdapter`)

**What gets tracked automatically:**
- Provider, model name, tokens in/out, calculated cost (USD), duration
- Rate limiting per user/org/provider (configurable via env vars)

**Architecture:** Adapter pattern — each provider implements `chat`, `completion`, and `list_models` with a unified response format. `Ai::ProxyService` orchestrates adapter selection and usage tracking.

**Limitation:** This only works when developers make raw API calls. It does **not** intercept requests made by IDE-integrated tools like Cursor, Copilot, or Claude Code, which use their own API keys and endpoints.

### 4.2 Telemetry Ingestion (Agent Mode)

**How it works:** An external agent (CLI tool, IDE extension, or browser plugin) collects usage data from the developer's environment and POSTs it to DB90.

**Endpoints:**
- `POST /api/v1/organizations/:org_id/telemetry/ingest` — single event
- `POST /api/v1/organizations/:org_id/telemetry/batch` — batch (up to 100 events)

**Processing pipeline:**
1. Raw payload stored in MinIO with AES-256-GCM encryption
2. Temporal workflow started (`IngestionSanitizationWorkflow`)
3. Classification, sanitization, persistence, alerting
4. Fallback: direct database insert if Temporal is unavailable

**Accepted fields:** `tool_name`, `event_type`, `model`, `tokens_in`, `tokens_out`, `cost_usd`, `duration_ms`, `occurred_at`, `project_id`, `metadata` (JSONB)

**Limitation:** The telemetry endpoint is fully implemented, but **no client-side agent or IDE extension exists in this repository**. The endpoint is a receiver with no corresponding sender.

### 4.3 Webhooks (Passive Collection)

**How it works:** External services push events to DB90 via webhook endpoints. DB90 verifies the signature and routes the payload to a provider-specific sync job.

**Endpoint:** `POST /api/v1/webhooks/:provider/:connector_id`

**Supported providers:** GitHub, GitLab, Bitbucket, Jira, Linear

**What gets collected:** Repository activity (commits, PRs, issues) — contextual data, not AI usage data.

**Limitation:** Webhooks provide git/project activity but **no direct AI usage metrics**. They can enrich attribution (e.g., correlating a Copilot-assisted commit to a user) but cannot measure token consumption.

### 4.4 Limitations and Gaps

This is the most critical section of this analysis.

**The fundamental problem:** None of the popular AI coding tools expose usage telemetry APIs:

| Tool | Exposes Usage Data Externally? | Notes |
|---|---|---|
| Cursor | No | Closed-source, no extension API for usage data |
| GitHub Copilot | Partial | Copilot Metrics API exists for GitHub org admins; not integrated in DB90 |
| Windsurf | No | No API |
| Claude Code | No | CLI tool, no telemetry export |
| Aider | No | Open-source but no built-in telemetry export |
| Continue | Possible | Open-source; could be forked to add telemetry |
| Cody (Sourcegraph) | Partial | Only via Sourcegraph's own platform |

**What is missing to close the gap:**

1. **Client-side agents/extensions** — A VS Code extension, Cursor extension, or CLI daemon that intercepts or observes AI API traffic from the developer's machine and sends telemetry to DB90. **Not implemented.**

2. **Network-level proxy** — A transparent HTTP proxy (mitmproxy-style) that sits between the developer and AI API endpoints, logging requests. DB90's AI Gateway is an application-level proxy, not a transparent one. **Not implemented.**

3. **GitHub Copilot Metrics API integration** — GitHub provides a REST API for Copilot usage metrics at the organization level. This could be integrated via the existing `GithubSyncJob`. **Not implemented.**

4. **Provider billing API integration** — OpenAI, Anthropic, and others provide usage/billing APIs. These could be polled to backfill aggregate usage data. **Not implemented.**

**In its current state, DB90 can reliably track AI usage only through the AI Gateway proxy** — which requires developers to route their API calls through DB90 instead of calling providers directly. For IDE-integrated tools (Cursor, Copilot, Windsurf), there is no working data collection mechanism.

---

## 5. Database Architecture

### 5.1 TimescaleDB and Time-Series Design

The database uses PostgreSQL 17 with the **TimescaleDB** extension. The schema is split into two logical areas:

- **`public` schema** — relational data (users, organizations, projects, connectors)
- **`timeseries` schema** — time-series data stored in TimescaleDB hypertables

Hypertables:
- `timeseries.tool_events` — individual AI usage events
- `timeseries.hourly_token_usage` — pre-aggregated hourly metrics
- `timeseries.daily_token_usage` — pre-aggregated daily metrics

The schema format is SQL (`config.active_record.schema_format = :sql`) to preserve TimescaleDB-specific constructs, custom types, and hypertable definitions.

### 5.2 Custom Enums

```sql
-- AI tools tracked
CREATE TYPE tool_name AS ENUM (
  'claude_code', 'cursor', 'windsurf', 'github_copilot',
  'aider', 'continue', 'cody', 'tabnine', 'amazon_q',
  'openrouter', 'anthropic_api', 'openai_api', 'gemini_api', 'custom'
);

-- Event types
CREATE TYPE event_type AS ENUM (
  'chat', 'completion', 'edit', 'commit', 'review',
  'test', 'debug', 'refactor', 'documentation', 'other'
);

-- Organization/project roles
CREATE TYPE member_role AS ENUM ('owner', 'admin', 'member', 'viewer');

-- Connector types
CREATE TYPE connector_type AS ENUM (
  'github', 'gitlab', 'bitbucket', 'jira', 'linear',
  'openrouter', 'anthropic', 'openai', 'gemini'
);

-- Risk levels for audit logs
CREATE TYPE risk_level AS ENUM ('low', 'medium', 'high', 'critical');

-- Retention policy enums
CREATE TYPE raw_event_ttl AS ENUM ('6_hours', '12_hours', '24_hours', '48_hours', '72_hours');
CREATE TYPE tool_events_retention AS ENUM ('30_days', '60_days', '90_days', '180_days', '365_days', '730_days');
CREATE TYPE hourly_aggregate_retention AS ENUM ('90_days', '180_days', '365_days', '730_days');
CREATE TYPE daily_aggregate_retention AS ENUM ('365_days', '730_days', '1095_days', 'forever');
```

### 5.3 Complete Table Reference

| Table | Schema | Purpose | Key Columns |
|---|---|---|---|
| `users` | public | User accounts (synced from Keycloak) | `keycloak_sub`, `email`, `name`, `global_admin` |
| `organizations` | public | Multi-tenant organizations | `name`, `slug`, `is_active` |
| `organization_memberships` | public | User-org relationships | `user_id`, `organization_id`, `role` |
| `organization_settings` | public | Key-value org config | `organization_id`, `key`, `value` (JSONB) |
| `organization_retention_policies` | public | Data retention rules | `raw_event_ttl`, `tool_events_retention`, `hourly_aggregate_retention`, `daily_aggregate_retention` |
| `organization_connectors` | public | OAuth integrations | `connector_type`, `access_token` (encrypted), `webhook_secret` (encrypted) |
| `projects` | public | Projects (org or personal) | `name`, `slug`, `organization_id`, `owner_id` |
| `project_memberships` | public | User-project relationships | `user_id`, `project_id`, `role` |
| `project_settings` | public | Key-value project config | `project_id`, `key`, `value` (JSONB) |
| `repositories` | public | Git repositories | `external_id`, `name`, `full_name`, `url` |
| `invitations` | public | Org invitations with tokens | `email`, `token`, `role`, `expires_at` |
| `user_settings` | public | Key-value user preferences | `user_id`, `key`, `value` (JSONB) |
| `user_tool_accounts` | public | User tool account mappings | `tool_name`, `external_user_id`, `access_token` (encrypted) |
| `sanitization_policies` | public | Versioned data sanitization rules | `version`, `classification_rules` (JSONB), `sanitization_rules` (JSONB) |
| `audit_logs` | public | Risk scanning audit trail | `risk_level`, `confidence_score`, `classification_labels`, `temporal_workflow_id` |
| `admin_audit_logs` | public | Admin action tracking | `action`, `resource_type`, `tracked_changes`, `ip_address` |
| `tool_events` | timeseries | AI usage events (hypertable) | `tool_name`, `event_type`, `model`, `tokens_in`, `tokens_out`, `cost_usd`, `occurred_at` |
| `hourly_token_usage` | timeseries | Hourly aggregates (hypertable) | `bucket`, `tool_name`, `model`, `tokens_in`, `tokens_out`, `cost_usd`, `event_count` |
| `daily_token_usage` | timeseries | Daily aggregates (hypertable) | `bucket`, `tool_name`, `model`, `tokens_in`, `tokens_out`, `cost_usd`, `event_count` |

All primary keys are UUIDs. Encrypted fields use Rails `encrypts` (ActiveRecord Encryption).

---

## 6. Domain Models

### 6.1 User and Access Control

**`User`** — Synced from Keycloak on each JWT-authenticated request via `UserSyncService`. Fields `keycloak_sub` and `email` are unique. `global_admin` grants access to the admin panel and impersonation.

**`UserSetting`** — Key-value store for user preferences. Class methods `get(user, key)` and `set(user, key, value)`.

**`UserToolAccount`** — Links a user's external tool identity (e.g., GitHub username, OpenAI account) to their organization membership. Used by `CorrelationService` for event attribution. Tokens are encrypted.

### 6.2 Organization and Multi-Tenancy

**`Organization`** — The primary tenant boundary. All tool events, projects, connectors, and audit logs are scoped to an organization. Auto-generates a URL-safe `slug`. Creates a default `OrganizationRetentionPolicy` on creation.

**`OrganizationMembership`** — Links users to organizations with a role (`owner`, `admin`, `member`, `viewer`). The role determines authorization via ActionPolicy.

**`OrganizationSetting`** — Key-value store for org configuration (e.g., cost alert thresholds).

**`OrganizationConnector`** — OAuth credentials for external services. Encrypted `access_token`, `refresh_token`, `webhook_secret`. Unique per `(organization_id, connector_type)`. Methods: `source_control?`, `project_management?`, `ai_provider?`.

**`Invitation`** — Email-based invitations with a unique token, role assignment, and 7-day expiration. Statuses: `pending`, `accepted`, `revoked`, `expired`.

### 6.3 Projects and Repositories

**`Project`** — Can belong to an organization (team project) or a user (personal project), enforced by validation. Scoped to an org via `organization_id` or to a user via `owner_id`.

**`ProjectMembership`** — Same role structure as organization memberships.

**`Repository`** — A git repository linked to a project via an `OrganizationConnector`. Tracks `external_id`, `full_name`, `url`, `default_branch`, `last_sync_at`.

### 6.4 Tool Events and Analytics

**`ToolEvent`** — The central data model. Stored in `timeseries.tool_events` (TimescaleDB hypertable). Tracks 14 tool names and 10 event types. Key fields: `tool_name`, `event_type`, `model`, `tokens_in`, `tokens_out`, `tokens_total`, `cost_usd`, `duration_ms`, `occurred_at`, `metadata` (JSONB). Auto-calculates `tokens_total` if blank.

**`HourlyTokenUsage`** / **`DailyTokenUsage`** — Read-only pre-aggregated views. Queried by `StatsController` for dashboard charts.

**`AuditLog`** — Attached to a `ToolEvent` after Temporal workflow processing. Records `risk_level`, `confidence_score`, `classification_labels`, `sanitization_actions`, and the `temporal_workflow_id`.

### 6.5 Connectors and Integrations

Nine connector types organized into three categories:

| Category | Types |
|---|---|
| Source Control | `github`, `gitlab`, `bitbucket` |
| Project Management | `jira`, `linear` |
| AI Providers | `openrouter`, `anthropic`, `openai`, `gemini` |

Each connector stores OAuth tokens (encrypted), webhook secrets, sync timestamps, and error state.

### 6.6 Governance and Compliance

**`OrganizationRetentionPolicy`** — Configurable data retention with compliance-labeled presets:

| Data Tier | Options | Default |
|---|---|---|
| Raw Events (MinIO) | 6h, 12h, 24h, 48h, 72h | 24 hours |
| Tool Events | 30d, 60d, 90d, 180d, 365d, 730d | 90 days |
| Hourly Aggregates | 90d, 180d, 365d (SOC2), 730d (HIPAA) | 365 days |
| Daily Aggregates | 365d, 730d, 1095d, Forever | Forever |

**`SanitizationPolicy`** — Versioned, globally-scoped rules for event classification and sanitization. Only one policy is active at a time. Fields: `classification_rules` (JSONB), `sanitization_rules` (JSONB).

**`AdminAuditLog`** — Tracks all admin panel actions with `action`, `resource_type`, `resource_id`, `tracked_changes`, `ip_address`, `user_agent`.

---

## 7. API Reference

### 7.1 Authentication and Authorization

**Authentication:** JWT tokens issued by Keycloak. The `JwtAuth` middleware validates tokens and injects claims into `request.env['jwt.claims']`. `UserSyncService` upserts the user record from JWT claims on each request.

**Organization context:** Set via `X-Organization-ID` request header or URL parameter.

**Authorization:** ActionPolicy policies enforce role-based access:

| Policy | Governs |
|---|---|
| `OrganizationPolicy` | Org CRUD, settings, retention policies |
| `ProjectPolicy` | Project CRUD, settings |
| `OrganizationMembershipPolicy` | Member management |
| `ProjectMembershipPolicy` | Project member management |
| `OrganizationConnectorPolicy` | Connector CRUD, OAuth flows |
| `ToolEventPolicy` | Event visibility |
| `InvitationPolicy` | Invitation management |
| `RepositoryPolicy` | Repository CRUD |
| `UserPolicy` | Profile management |
| `UserToolAccountPolicy` | Tool account management |

**Internal API:** Authenticated via `INTERNAL_API_KEY` Bearer token (for Temporal workers and internal services).

### 7.2 API V1 Endpoints

#### Users

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/users/me` | Current user profile |
| PATCH | `/api/v1/users/me` | Update profile |
| GET | `/api/v1/users/me/organizations` | User's organizations |
| GET | `/api/v1/users/me/settings` | User settings |
| PUT | `/api/v1/users/me/settings/:key` | Update setting |
| DELETE | `/api/v1/users/me/settings/:key` | Delete setting |

#### Organizations

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/organizations` | List (scoped by membership) |
| POST | `/api/v1/organizations` | Create (caller becomes owner) |
| GET | `/api/v1/organizations/:id` | Show |
| PATCH | `/api/v1/organizations/:id` | Update (admin+) |
| DELETE | `/api/v1/organizations/:id` | Destroy (owner only) |
| GET | `/api/v1/organizations/:id/retention_policy` | Get retention policy |
| PATCH | `/api/v1/organizations/:id/retention_policy` | Update retention policy |
| GET | `/api/v1/organizations/:id/settings` | List settings |
| PUT | `/api/v1/organizations/:id/settings/:key` | Set a setting |
| DELETE | `/api/v1/organizations/:id/settings/:key` | Delete a setting |

#### Organization Members

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/organizations/:org_id/members` | List with token stats |
| POST | `/api/v1/organizations/:org_id/members` | Add member |
| GET | `/api/v1/organizations/:org_id/members/:id` | Show |
| PATCH | `/api/v1/organizations/:org_id/members/:id` | Update role |
| DELETE | `/api/v1/organizations/:org_id/members/:id` | Remove member |
| GET | `/api/v1/organizations/:org_id/members/:id/stats` | Detailed member stats |
| GET | `/api/v1/organizations/:org_id/members/:id/events` | Member events |

#### Invitations

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/organizations/:org_id/invitations` | List |
| POST | `/api/v1/organizations/:org_id/invitations` | Create (sends email) |
| GET | `/api/v1/organizations/:org_id/invitations/:id` | Show |
| POST | `/api/v1/organizations/:org_id/invitations/:id/resend` | Resend |
| DELETE | `/api/v1/organizations/:org_id/invitations/:id` | Revoke |
| GET | `/api/v1/invitations/:token` | View invitation (public) |
| POST | `/api/v1/invitations/:token/accept` | Accept invitation |
| GET | `/api/v1/invitations/check` | Check pending invitations |

#### Connectors

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/organizations/:org_id/connectors` | List |
| POST | `/api/v1/organizations/:org_id/connectors` | Create |
| GET | `/api/v1/organizations/:org_id/connectors/:id` | Show |
| PATCH | `/api/v1/organizations/:org_id/connectors/:id` | Update |
| DELETE | `/api/v1/organizations/:org_id/connectors/:id` | Delete |
| POST | `/api/v1/organizations/:org_id/connectors/:id/test` | Test connection |
| POST | `/api/v1/organizations/:org_id/connectors/:id/sync` | Trigger sync |
| GET | `/api/v1/organizations/:org_id/connectors/authorize/:type` | Get OAuth URL |
| POST | `/api/v1/organizations/:org_id/connectors/callback` | OAuth callback |

#### Projects

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/projects` | List (filter: `?personal=true` or `?organization_id=X`) |
| POST | `/api/v1/projects` | Create personal project |
| GET | `/api/v1/projects/:id` | Show |
| PATCH | `/api/v1/projects/:id` | Update |
| DELETE | `/api/v1/projects/:id` | Destroy |
| GET | `/api/v1/projects/:id/stats` | Project stats |
| GET | `/api/v1/projects/:id/stats/daily_by_tool` | Daily breakdown by tool |
| GET | `/api/v1/projects/:id/members` | List members |
| GET | `/api/v1/organizations/:org_id/projects` | List org projects |
| POST | `/api/v1/organizations/:org_id/projects` | Create org project |

#### Project Members

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/projects/:project_id/members` | List |
| POST | `/api/v1/projects/:project_id/members` | Add |
| GET | `/api/v1/projects/:project_id/members/:id` | Show |
| PATCH | `/api/v1/projects/:project_id/members/:id` | Update role |
| DELETE | `/api/v1/projects/:project_id/members/:id` | Remove |

#### Repositories

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/projects/:project_id/repositories` | List |
| POST | `/api/v1/projects/:project_id/repositories` | Add |
| GET | `/api/v1/projects/:project_id/repositories/:id` | Show |
| PATCH | `/api/v1/projects/:project_id/repositories/:id` | Update |
| DELETE | `/api/v1/projects/:project_id/repositories/:id` | Remove |
| POST | `/api/v1/projects/:project_id/repositories/:id/sync` | Trigger sync |

#### Tool Events

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/organizations/:org_id/events` | List (filterable by tool, type, user, project, date range) |
| GET | `/api/v1/organizations/:org_id/events/:id` | Show |
| GET | `/api/v1/organizations/:org_id/events/summary` | Summary stats |
| GET | `/api/v1/organizations/:org_id/events/unattributed` | Unattributed events |
| GET | `/api/v1/organizations/:org_id/events/:id/audit_trail` | Event audit log |

#### Telemetry Ingestion

| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/organizations/:org_id/telemetry/ingest` | Ingest single event |
| POST | `/api/v1/organizations/:org_id/telemetry/batch` | Batch ingest (up to 100) |

#### Statistics

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/organizations/:org_id/stats/overview` | Overview (total events, cost, active users, MoM change) |
| GET | `/api/v1/organizations/:org_id/stats/hourly` | Hourly breakdown |
| GET | `/api/v1/organizations/:org_id/stats/daily` | Daily breakdown with tool summary |
| GET | `/api/v1/organizations/:org_id/stats/daily_by_tool` | Daily by tool (for stacked charts) |
| GET | `/api/v1/organizations/:org_id/stats/heatmap` | Year-long activity heatmap |

#### AI Gateway

| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/organizations/:org_id/ai/:provider/completions` | Text completion proxy |
| POST | `/api/v1/organizations/:org_id/ai/:provider/chat` | Chat completion proxy |
| GET | `/api/v1/organizations/:org_id/ai/:provider/models` | List available models |

Supported `:provider` values: `openrouter`, `anthropic`, `openai`, `gemini`

#### Webhooks

| Method | Path | Description |
|---|---|---|
| POST | `/api/v1/webhooks/:provider/:connector_id` | Receive webhook (GitHub, GitLab, Bitbucket, Jira, Linear) |

#### User Tool Accounts

| Method | Path | Description |
|---|---|---|
| GET | `/api/v1/organizations/:org_id/tool_accounts` | List (current user) |
| POST | `/api/v1/organizations/:org_id/tool_accounts` | Link account |
| GET | `/api/v1/organizations/:org_id/tool_accounts/:id` | Show |
| PATCH | `/api/v1/organizations/:org_id/tool_accounts/:id` | Update |
| DELETE | `/api/v1/organizations/:org_id/tool_accounts/:id` | Unlink |

### 7.3 Internal API

Authenticated via `INTERNAL_API_KEY` Bearer token. Used by Temporal workers.

| Method | Path | Description |
|---|---|---|
| POST | `/api/internal/tool_events` | Create tool event (from workflow) |
| POST | `/api/internal/audit_logs` | Create audit log |
| POST | `/api/internal/alerts` | Create alert (broadcasts via ActionCable) |
| POST | `/api/internal/broadcasts` | Broadcast message |
| GET | `/api/internal/organizations/:id/sanitization_policy` | Get current sanitization policy |

### 7.4 Admin Panel

Mounted at `/admin`. Requires `global_admin` flag on the user. Powered by Administrate. All actions logged to `AdminAuditLog`.

**Features:**
- Full CRUD for organizations, users, projects, connectors, memberships, repositories, sanitization policies, user tool accounts
- Read-only views for audit logs, admin audit logs, tool events
- Special actions: user impersonation, force sync connectors, activate/deactivate sanitization policies
- CSV/JSON export, batch delete

---

## 8. Services Layer

### 8.1 AI Gateway Services

**`Ai::ProxyService`** — Orchestrator. Selects the correct adapter based on provider name, proxies the request, and tracks usage as a `ToolEvent`.

**`Ai::OpenaiAdapter`** — OpenAI Chat Completions API (`/v1/chat/completions`). Default model: `gpt-4o`. Hardcoded pricing for 7 models.

**`Ai::AnthropicAdapter`** — Anthropic Messages API (`/v1/messages`). Default model: `claude-3-5-sonnet-20241022`. Converts OpenAI-style message format to Anthropic format (separate system message). Hardcoded pricing for 5 models.

**`Ai::GeminiAdapter`** — Google Gemini API (`/v1beta/models/:model:generateContent`). Default model: `gemini-1.5-pro`. Converts messages to Gemini's `contents` format (`assistant` → `model` role). Hardcoded pricing for 3 models.

**`Ai::OpenrouterAdapter`** — OpenRouter API (OpenAI-compatible). Routes to any model supported by OpenRouter.

**`Ai::CorrelationService`** — Attempts to attribute unattributed `ToolEvent` records to users. Applies correlation strategies in confidence order:
1. Direct `user_id` (confidence: 1.0)
2. Email match (confidence: 0.95)
3. Tool account `external_user_id` (confidence: 0.9)
4. Git author email (confidence: 0.85)
5. Machine ID (confidence: 0.7)
6. IP address within 24h window (confidence: 0.5)

Only attributes events with confidence ≥ 0.7.

**`ModelPricingService`** — Calculates costs from token counts using per-model and per-tool pricing tables.

### 8.2 OAuth Providers

All inherit from `Oauth::BaseProvider`:

| Provider | OAuth Flow | Capabilities |
|---|---|---|
| `Oauth::GithubProvider` | GitHub OAuth2 | Repository listing, webhook management |
| `Oauth::GitlabProvider` | GitLab OAuth2 | Repository listing, webhook management |
| `Oauth::BitbucketProvider` | Bitbucket OAuth2 | Repository listing, webhook management |
| `Oauth::JiraProvider` | Atlassian OAuth2 | Project listing |
| `Oauth::LinearProvider` | Linear OAuth2 | Project/team listing |

### 8.3 Webhook Verification

Each provider has a signature verifier:

| Verifier | Signature Header | Algorithm |
|---|---|---|
| `Webhooks::GithubVerifier` | `X-Hub-Signature-256` | HMAC-SHA256 |
| `Webhooks::GitlabVerifier` | `X-Gitlab-Token` | Token comparison |
| `Webhooks::BitbucketVerifier` | `X-Hub-Signature` | HMAC-SHA256 |
| `Webhooks::JiraVerifier` | Custom | HMAC-SHA256 |
| `Webhooks::LinearVerifier` | `Linear-Signature` | HMAC-SHA256 |

### 8.4 Data Processing Services

**`RawEventStore`** — S3 wrapper for MinIO. Encrypts payloads with AES-256-GCM before storage. Key format: `{org_id}/{YYYY/MM/DD/HH}/{uuid}.enc`. Auto-creates bucket with 3-day lifecycle expiration policy.

**`RetentionService`** — Provides retention policy lookups and cutoff date calculations. Labels include compliance references (SOC2 for 365d, HIPAA for 730d).

**`UserSyncService`** — Syncs user records from Keycloak JWT claims. Maps `sub` → `keycloak_sub`, `email`, `name`, `picture`. Handles existing users by email (backfills `keycloak_sub`). Can auto-assign users to organizations based on email domain.

**`ImpersonationService`** — Generates short-lived JWT tokens (1 hour) for admin impersonation. Includes impersonator metadata in the token.

**`Temporal::Client`** — Wrapper around the Temporal Ruby SDK. Methods: `start_workflow`, `execute_workflow`, `query_workflow`, `signal_workflow`.

---

## 9. Background Jobs

All jobs use Sidekiq.

| Job | Queue | Purpose |
|---|---|---|
| `AttributionJob` | `ai` | Batch-correlates unattributed events to users via `CorrelationService` |
| `OrgRetentionCleanupJob` | default | Deletes tool events older than org retention policy cutoff |
| `CostAlertJob` | `alerts` | Checks daily ($100), weekly ($500), monthly ($2000) and per-user thresholds; broadcasts via ActionCable |
| `AiUsageSyncJob` | default | Syncs AI usage data from providers |
| `GithubSyncJob` | default | Processes GitHub webhooks, syncs repositories |
| `GitlabSyncJob` | default | Processes GitLab webhooks, syncs repositories |
| `BitbucketSyncJob` | default | Processes Bitbucket webhooks, syncs repositories |
| `JiraSyncJob` | default | Processes Jira webhooks |
| `LinearSyncJob` | default | Processes Linear webhooks |

---

## 10. Temporal Workflows

**`IngestionSanitizationWorkflow`** — The main event processing pipeline, triggered when a telemetry event is ingested:

```
┌─────────────────────────────┐
│  1. FetchRawEventActivity   │  Retrieve encrypted raw event from MinIO
└────────────┬────────────────┘
             ▼
┌─────────────────────────────┐
│  2. ClassificationActivity  │  Classify event, assess risk level
└────────────┬────────────────┘
             ▼
┌─────────────────────────────┐
│  3. GetPolicyActivity       │  Fetch current active sanitization policy
└────────────┬────────────────┘
             ▼
┌─────────────────────────────┐
│  4. SanitizationActivity    │  Apply sanitization rules to event data
└────────────┬────────────────┘
             ▼
┌─────────────────────────────┐
│  5. PersistenceActivity     │  Save ToolEvent + AuditLog to database
└────────────┬────────────────┘
             ▼
┌─────────────────────────────┐
│  6. AlertActivity           │  Generate alerts for high-risk events
└────────────┬────────────────┘
             ▼
┌─────────────────────────────┐
│  7. BroadcastActivity       │  Push real-time update via ActionCable
└─────────────────────────────┘
```

Temporal provides durable execution: if any activity fails, it is automatically retried. The entire workflow state is persisted, enabling replay and debugging via the Temporal UI at `localhost:8088`.

---

## 11. Infrastructure

### 11.1 Docker Services

Defined in `docker-compose.yml`:

| Service | Image | Port(s) | Purpose |
|---|---|---|---|
| postgres | TimescaleDB (PG17) | 5432 | Primary database |
| redis | Redis 7 Alpine | 6379 | Cache, Sidekiq queues |
| minio | MinIO | 9000, 9001 | S3-compatible object storage |
| temporal | Temporal | 7233 | Workflow orchestration engine |
| temporal-ui | Temporal UI | 8088 | Workflow monitoring dashboard |
| keycloak | Keycloak | 8080 | OIDC authentication server |

### 11.2 CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/ci.yml`):

| Job | Tools | Purpose |
|---|---|---|
| `lint-api` | Rubocop | Ruby code style |
| `lint-web` | ESLint | TypeScript/React code style |
| `test-api` | RSpec + PostgreSQL + Redis services | Backend tests |
| `test-web` | Vitest | Frontend unit tests |
| `build` | Docker | Build images for API, Web, Temporal Worker |
| `security` | Brakeman + Bundler Audit | Security vulnerability scanning |

### 11.3 Deployment

**Kamal** (Rails' default deployment tool) configured in `config/deploy.yml`:
- Docker multi-stage builds (Ruby 3.4.8-slim base, jemalloc, bootsnap precompilation)
- Non-root user (`rails:rails`)
- Automatic `rails db:prepare` on container startup
- Three Dockerfiles: `Dockerfile.api`, `Dockerfile.web`, `Dockerfile.temporal-worker`

---

## 12. Implementation Status

| Component | Status | Notes |
|---|---|---|
| Database schema (21 tables) | **Complete** | TimescaleDB hypertables, custom enums, encryption |
| REST API (60+ endpoints) | **Complete** | Full CRUD, pagination, filtering, error handling |
| Authentication (Keycloak) | **Complete** | JWT middleware, user sync |
| Authorization (ActionPolicy) | **Complete** | 10 policies with role-based rules |
| AI Gateway (4 providers) | **Complete** | Adapter pattern, rate limiting, cost tracking |
| Telemetry ingestion endpoint | **Complete** | Single + batch, Temporal fallback |
| Temporal workflow pipeline | **Complete** | 7-step ingestion/sanitization workflow |
| OAuth connectors (5 providers) | **Complete** | Token management, refresh, webhook setup |
| Webhook receivers (5 providers) | **Complete** | Signature verification, async processing |
| Correlation/attribution engine | **Complete** | 6 strategies with confidence scoring |
| Retention policies | **Complete** | Per-org configurable, compliance labels |
| Cost alerting | **Complete** | Configurable thresholds, ActionCable broadcast |
| Admin panel | **Complete** | Full CRUD, impersonation, audit logging |
| Serializers | **Complete** | Alba-based, multiple detail levels |
| Background jobs (9 jobs) | **Complete** | Sidekiq-based, retry policies |
| API documentation (Swagger) | **Complete** | OpenAPI 3.0 spec |
| CI/CD pipeline | **Complete** | Lint, test, build, security scan |
| Docker infrastructure | **Complete** | 6 services, 3 Dockerfiles |
| Test suite | **Partial** | Structure exists; coverage depth varies |
| **Client-side telemetry agent** | **Not Started** | No IDE extension, CLI tool, or browser plugin |
| **Transparent network proxy** | **Not Started** | AI Gateway is app-level only |
| **Copilot Metrics API integration** | **Not Started** | GitHub connector only handles repos/webhooks |
| **Provider billing API polling** | **Not Started** | No integration with OpenAI/Anthropic usage APIs |

---

## 13. Critical Gaps and Recommendations

### Gap 1: No Client-Side Data Collection Agent

**Problem:** DB90 declares support for 14 tools (Cursor, Copilot, Claude Code, Windsurf, etc.) but has no mechanism to collect usage data from any of them. These tools use their own API keys, their own endpoints, and do not expose telemetry.

**Recommendation:** Build one or more of:
- **VS Code / Cursor extension** that observes LLM API calls from the Extension Host and reports telemetry to DB90
- **CLI agent / daemon** that monitors network traffic to known AI API endpoints and reports summaries
- **Git hook integration** that detects AI-generated code patterns in commits

### Gap 2: No GitHub Copilot Metrics API Integration

**Problem:** GitHub provides a [Copilot Metrics API](https://docs.github.com/en/rest/copilot/copilot-usage) for organization admins. DB90 has a GitHub connector but only uses it for repository sync and webhooks.

**Recommendation:** Extend `GithubSyncJob` to poll the Copilot Usage API and ingest aggregate metrics as `ToolEvent` records.

### Gap 3: Hardcoded and Outdated Model Pricing

**Problem:** AI adapter pricing is hardcoded in each adapter class (e.g., `AnthropicAdapter::PRICING`) with comments "as of 2024." Model names reference older versions (e.g., `claude-3-5-sonnet-20241022`).

**Recommendation:** Move pricing to a database table or external configuration. Add a scheduled job to refresh pricing from provider APIs or a pricing service.

### Gap 4: No Streaming Support in AI Gateway

**Problem:** `AiGatewayController` accepts a `stream` parameter in chat options, but none of the adapters implement streaming. All requests are synchronous request-response.

**Recommendation:** Implement SSE (Server-Sent Events) or WebSocket streaming for the AI Gateway to support real-time responses, which is the expected behavior for chat interfaces.

### Gap 5: User Attribution in AI Gateway

**Problem:** In `Ai::ProxyService#track_usage`, the user_id is set to `connector.organization.members.first&.id` with a comment "Will be replaced by correlation." This means all AI Gateway usage is attributed to the first org member.

**Recommendation:** Pass `current_user` from the controller through to `track_usage` so events are correctly attributed to the requesting user.
