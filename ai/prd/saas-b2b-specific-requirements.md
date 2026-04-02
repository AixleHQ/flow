# SaaS B2B Specific Requirements

## Project-Type Overview

Aixle is a B2B SaaS platform for orchestration of AI agents with a workflow system. The focus is on simplicity and minimal overhead for internal use, with the ability to scale to external clients.

## Multi-Tenancy Model

**Approach:** Shared database with company_id (simplest option)

```
┌─────────────────────────────────────────────────────────────┐
│ PostgreSQL (shared)                                         │
│                                                             │
│  companies (id, name, settings)                             │
│       │                                                     │
│       ├── users (id, company_id, email, role)               │
│       │                                                     │
│       ├── projects (id, company_id, name)                   │
│       │       │                                             │
│       │       └── project_collaborators (project_id, user_id)│
│       │                                                     │
│       ├── workflows (id, company_id, ...)                   │
│       │                                                     │
│       ├── secrets (id, company_id, ...)                     │
│       │                                                     │
│       └── usage_events (id, company_id, ...)                │
└─────────────────────────────────────────────────────────────┘
```

**Isolation:** All queries are filtered by company_id. Row-level security at the application level.

## Permission Model (RBAC)

**Simplified model for MVP:**

| Role | Scope | Permissions |
|------|-------|-------------|
| **Admin** | Company | Full access: users, workflows, secrets, tools, billing |
| **Collaborator** | Project | Read/Write: sessions, artifacts, workflows within project |

**No Viewer role for MVP** — all project participants have write access.

**Project-level collaboration:**
- Projects belong to Company
- Users are added as Collaborators to specific Projects
- Collaborators have full read/write within their Projects

## Subscription Tiers

**TBD** — to be defined later. The MVP works without a billing model.

## Integration Architecture

**Core Integrations (MVP):**

| Integration | Type | Purpose |
|-------------|------|---------|
| **Linear** | Native | Task export from planning workflows |
| **GitHub/GitLab** | Native | PR creation, code context loading |
| **S3** | Native | Artifact storage |
| **LLM Providers** | Native | Anthropic, OpenAI, OpenRouter |

**Extensible via Tools:**

| Integration | Implementation | Notes |
|-------------|----------------|-------|
| **Slack** | Custom Tool | Read channels, send notifications |
| **Jira** | Custom Tool | Alternative to Linear |
| **Confluence** | Custom Tool | Documentation sync |
| **Other** | Custom Tool | Any HTTP API via Tool framework |

**Tool Framework:** Integrations that are not critical for the MVP are implemented through an extensible Tools system (Docker containers + secrets).

## Implementation Considerations

**Database:**
- PostgreSQL with company_id on all tenant tables
- Indexes on (company_id, ...) for query performance
- No schema-per-tenant complexity

**Authentication:**
- Google OAuth (already implemented)
- Company assignment on first login or invite

**Authorization:**
- Application-level RBAC
- Project-scoped collaborator checks
- No complex permission inheritance for MVP

---
