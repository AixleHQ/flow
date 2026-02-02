# Architecture Decision Document

**Project:** Palad
**Status:** Complete
**Last Updated:** 2026-01-30

---

## Related Documents

| Document | Description |
|----------|-------------|
| [PRD](./prd.md) | Product Requirements Document |
| [Workflow Architecture](./workflow-architecture.md) | Workflow engine, execution flow, data models |
| [Implementation Notes](./implementation-notes.md) | Detailed implementation decisions |
| [UX Design Specification](./ux-design-specification.md) | UI/UX patterns |

---

## 1. Project Overview

**Palad** — a cloud SaaS B2B platform for orchestrating AI coding agents with a workflow system.

### Core Features
- Multi-agent sessions (Claude Code, Cursor CLI, Codex, Gemini CLI)
- BMAD-style workflow execution with artifacts
- MITM proxy billing
- Shared configuration (workflows, prompts, secrets)

### Team
- Artem — BMAD method, UI, workflows
- Andrey — AI part, agents, integrations
- Alexander — Full-stack development

---

## 2. Technology Stack

### Backend
| Component | Technology | Version |
|-----------|------------|---------|
| Framework | Ruby on Rails | 8.0.2 |
| Database | PostgreSQL | 15.3 |
| Cache | Redis | - |
| Orchestration | Temporal | - |
| Storage | AWS S3 | - |

### Frontend
| Component | Technology | Version |
|-----------|------------|---------|
| Framework | React | 19 |
| Language | TypeScript | 5.9.3 |
| Build | Vite | 7.3.1 |
| UI Library | Material UI | 6.4.7 |
| State | Redux Toolkit + Zustand | - |
| Routing | TanStack Router | - |

### Infrastructure
| Component | Technology |
|-----------|------------|
| Containers | Docker |
| Hosting | AWS ECS Fargate |
| CI/CD | GitHub Actions |

---

## 3. Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         FRONTEND                                 │
│  React SPA (Feature-Sliced Design)                              │
│  - Terminal (xterm.js)                                          │
│  - File Tree, File Viewer                                       │
│  - Workflow Stepper                                             │
└─────────────────────────────────────────────────────────────────┘
                              │ REST API
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         BACKEND                                  │
│  Rails API + Services                                           │
│  - ContainerService (Docker management)                         │
│  - TemporalService (Workflow orchestration)                     │
│  - AgentCredentialsService (Adapter pattern)                    │
└─────────────────────────────────────────────────────────────────┘
          │                   │                    │
          ▼                   ▼                    ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Docker     │    │   Temporal   │    │  PostgreSQL  │
│  Containers  │    │   Server     │    │   + Redis    │
│  (Agents)    │    │  (Workflows) │    │   + S3       │
└──────────────┘    └──────────────┘    └──────────────┘
```

### Key Architectural Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| API Pattern | REST | Standard, sufficient for all use cases |
| Auth | Google OAuth (session-based) | Simplicity for MVP |
| Authorization | Pundit RBAC | Flexible, per-resource policies |
| State Management | Redux Toolkit + Zustand | Global + local state separation |
| Workflow Orchestration | Temporal | Reliability, retry, visibility |
| Tool Calling | MCP Protocol | Standard for CLI agents |
| Container Isolation | Docker per session | Security, no cross-contamination |

---

## 4. Data Architecture

### Multi-tenancy Model

```
companies (tenant root)
    ├── users
    ├── projects
    │   └── project_collaborators
    ├── workflows
    ├── secrets
    └── usage_events
```

**Isolation:** All queries filtered by `company_id`. Row-level security at application level.

### Core Models

> Full data models for Workflow system: see [Workflow Architecture](./workflow-architecture.md#3-data-model)

| Model | Purpose |
|-------|---------|
| `User` | Platform users with roles |
| `Company` | Tenant (organization) |
| `Project` | Work container with collaborators |
| `TerminalSession` | Agent session with state machine |
| `AgentCredential` | Encrypted agent credentials |
| `Workflow` | Workflow definition |
| `WorkflowStep` | Step definition with instructions |
| `WorkflowRun` | Workflow execution instance |
| `StepRun` | Step execution instance |
| `Artifact` | Versioned file/document |

### State Machines (AASM)

**TerminalSession states:**
```
not_started → started → running → stopped → collected
                                          ↘ failed
                                          ↘ cancelled
```

**User states:**
- Account: `active`, `pending`, `suspended`, `archived`
- Onboarding: `step1` → `step2` → `step3` → `step4` → `completed`

---

## 5. Project Structure

```
app/
├── ai/                          # Planning & architecture docs
├── ai-engine/                   # Python AI Engine (Legacy)
├── docker/                      # Agent container images
│   ├── claude-code/
│   ├── cursor-cli/
│   ├── codex/
│   └── gemini-cli/
└── web/                         # Rails + React application
    ├── app/
    │   ├── controllers/api/v1/  # REST API
    │   ├── frontend/            # React SPA (Feature-Sliced Design)
    │   │   ├── app/
    │   │   ├── entities/
    │   │   ├── features/
    │   │   ├── pages/
    │   │   ├── shared/
    │   │   └── widgets/
    │   ├── models/
    │   ├── policies/            # Pundit authorization
    │   ├── serializers/
    │   ├── services/
    │   │   ├── agents/          # Agent adapters
    │   │   ├── container_service.rb
    │   │   └── temporal_service.rb
    │   └── temporal/
    │       ├── activities/
    │       └── workflows/
    ├── config/
    ├── db/
    └── test/controllers/        # Only controller tests
```

---

## 6. Implementation Patterns

### Naming Conventions

| Context | Convention | Example |
|---------|------------|---------|
| DB tables | snake_case, plural | `workflow_runs` |
| DB columns | snake_case | `created_at` |
| API endpoints | REST, plural | `/api/v1/projects` |
| React components | PascalCase | `WorkflowStepper.tsx` |
| Ruby classes | PascalCase | `WorkflowService` |
| Ruby methods | snake_case | `find_by_name` |
| TypeScript | camelCase | `workflowId` |

### API Response Format

```json
// List
{ "items": [...] }

// Single resource
{ "data": {...} }

// Error
{ "errors": {...} }
```

### Controller Pattern

```ruby
# Minimalist style with respond_with
def index
  users = current_company.users.ransack(params[:q]).result
  respond_with paginate(users)
end

def create
  user = current_company.users.create(user_params)
  respond_with user
end
```

### Authorization Pattern

Dynamic authorization via namespace base controller:
- Controller: `Api::V1::Company::UsersController`
- Policy: `Api::V1::Company::UsersPolicy`

### Frontend Case Conversion

Automatic camelCase ↔ snake_case via `baseApi.ts`:
- Request: `{ currentUser }` → `{ current_user }`
- Response: `{ current_user }` → `{ currentUser }`

---

## 7. Workflow System

> Full details: [Workflow Architecture](./workflow-architecture.md)

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Agent** | LLM configuration (persona, system prompt). Not tied to workflow |
| **Workflow** | Process definition: steps, inputs, outputs |
| **WorkflowStep** | Single step with instructions |
| **WorkflowRun** | Specific workflow execution |
| **StepRun** | Single step execution |
| **Artifact** | Versioned file/document |

### Workspace Structure

```
/workspace/
├── input/              # READONLY — input artifacts
└── output/             # COLLECT — agent outputs
```

### Implementation Phases

| Phase | Scope |
|-------|-------|
| 0 | Secrets Management |
| 1 | Agents (CRUD, selection) |
| 2 | Tools (Docker execution) |
| 3 | MCP Servers |
| 4 | Session Context (per-CLI config) |
| 5 | Workflows Core |
| 6 | Artifacts (versioning, S3) |
| 7 | Advanced (builder, non-interactive) |

### Dependency Graph

```
WORKFLOWS → SESSION CONTEXT → MCP SERVERS → TOOLS → AGENTS → SECRETS
```

---

## 8. Security

| Requirement | Implementation |
|-------------|----------------|
| Secrets encryption | ActiveSupport::MessageEncryptor (AES-256) |
| Data in transit | TLS 1.2+ |
| Multi-tenancy | company_id filtering, application-level |
| Container isolation | Docker per session |
| Audit logging | Structured JSON (Lograge) |

---

## 9. Quality Assurance

### Code Quality Checks (MANDATORY)

```bash
make check  # Runs inside Docker
```

**What it runs:**
1. `rails test` — all tests
2. `rubocop -a` — Ruby linting
3. `brakeman` — security scanning
4. `yarn lint:fix` — ESLint + Prettier

**Rule:** All checks must pass before commit.

### Testing Strategy

| Layer | Approach |
|-------|----------|
| Backend | Minitest, controller tests only |
| Frontend | Co-located tests (`*.test.tsx`) |
| Factories | FactoryBot with sequences |

---

## 10. Development Workflow

### Commands

```bash
bin/dev           # Rails + Vite dev servers
docker-compose up # Infrastructure (PostgreSQL, Redis, Temporal)
make check        # Run all quality checks
```

### Key Files

| File | Purpose |
|------|---------|
| `config/settings.yml` | Application settings |
| `.env.development` | Environment variables |
| `docker-compose.yml` | Development infrastructure |

---

## Architecture Status

**Overall:** READY FOR IMPLEMENTATION ✅

**Validation:**
- ✅ All decisions documented
- ✅ All requirements covered
- ✅ Patterns prevent conflicts
- ✅ Structure complete

---

_Document maintained by Winston (Architect Agent)_
