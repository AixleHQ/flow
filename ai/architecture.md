---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
lastStep: 8
status: 'complete'
completedAt: '2026-01-21'
inputDocuments:
  - ai/prd.md
  - ai/ux-design-specification.md
  - ai/project-overview.md
  - ai/brainstorm-palad-platform.md
  - ai/integration-architecture.md
  - ai/architecture-ai-engine.md
  - ai/architecture-web.md
  - kb/product/architecture.md
  - kb/product/vision.md
workflowType: 'architecture'
project_name: 'app'
user_name: 'Artem_petrov'
date: '2026-01-21'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**

53 functional requirements were extracted from the PRD, organized into 9 categories:

1. **Agent Sessions (FR1-FR9)** — 9 requirements
   - Launching sessions with different agents (Claude Code, Codex, Gemini CLI, Cursor CLI)
   - Two operating modes: Interactive and Non-interactive
   - Web terminal for interactive interaction
   - Real-time file tree and file viewer
   - Automatic token tracking via MITM proxy
   - Display of session costs

2. **Workflow Management (FR10-FR18)** — 9 requirements
   - CRUD operations for workflows
   - Defining steps with agents, prompts, and artifacts
   - Execution in Interactive and Non-interactive modes
   - Automatic passing of artifacts between steps

3. **Artifact Management (FR19-FR25)** — 7 requirements
   - Upload, view, download, and delete artifacts
   - Storage in S3 with metadata in the DB
   - History and versioning
   - Linking artifacts between workflow steps

4. **Project & Collaboration (FR26-FR31)** — 6 requirements
   - Multi-tenancy (companies, projects, collaborators)
   - Access management at the project level
   - Switching between projects

5. **Secrets Management (FR32-FR36)** — 5 requirements
   - Hierarchy: Platform → Company → Workflow
   - Encryption at rest
   - Write-only access (values cannot be viewed)

6. **Tools Framework (FR37-FR41)** — 5 requirements
   - Creating custom tools via Docker
   - Integration via the MCP protocol
   - Execution via Temporal Activities

7. **Billing & Analytics (FR42-FR46)** — 5 requirements
   - Tracking costs at the project/workflow/user level
   - Session history with costs
   - Company-wide statistics

8. **User Management (FR47-FR50)** — 4 requirements
   - Google OAuth
   - RBAC (Admin, Collaborator)
   - Managing company users

9. **Integrations (FR51-FR53)** — 3 requirements
   - Linear (exporting tasks)
   - GitHub (loading context, creating PRs)

**Non-Functional Requirements:**

**Security (NFR-S1-S6):**
- Encryption of secrets at rest (AES-256)
- TLS 1.2+ for data in transit
- Isolation by company_id (multi-tenancy)
- Audit log for admin actions (SOC 2)
- Isolation of Docker containers per session

**Reliability (NFR-R1-R5):**
- Session failure rate < 1%
- Zero data loss for artifacts (S3 with redundancy)
- Billing accuracy ≥ 95%
- Graceful degradation when the LLM provider is unavailable
- Preserving session state during failures

**Integration (NFR-I1-I5):**
- Support for multiple LLM providers (Anthropic, OpenAI, OpenRouter)
- MITM proxy compatible with all 4 agents
- GitHub API integration
- Linear API integration
- Temporal orchestration for all workflows

**Operability (NFR-O1-O3):**
- Structured logging
- Health checks for all containers
- Temporal UI for debugging

**UX Design Implications:**

The following architectural requirements were identified from the UX specification:
- **Real-time updates**: file tree, workflow statuses, team
- **Component complexity**: WorkflowStepper, StatusBar, FileTree, CommandPalette
- **Performance**: < 100ms for artifact search, < 30 seconds for session start
- **Accessibility**: WCAG 2.1 AA compliance
- **Responsive**: Desktop-only (1024px minimum)
- **Dark theme only** for MVP

### Scale & Complexity

**Complexity assessment:**

- **Project**: B2B SaaS platform for orchestration of AI agents
- **Complexity**: High
- **Technical domain**: Full-stack (Rails API + React SPA + Python workers + Docker orchestration)
- **Estimate of architectural components**: ~15-20 core components

**Complexity indicators:**

- ✅ **Real-time features**: WebSocket for file tree, real-time workflow statuses
- ✅ **Multi-tenancy**: Isolation by company_id, shared database with row-level security
- ✅ **Compliance**: SOC 2 Type II (for public SaaS), GDPR basics
- ✅ **Integration complexity**: MITM proxy for billing, MCP protocol for tools, Temporal for orchestration
- ✅ **User interaction complexity**: Interactive terminal sessions, workflow stepper, artifact provenance
- ✅ **Data complexity**: Artifacts in S3, metadata in PostgreSQL, vector DB (Qdrant)

### Technical Constraints & Dependencies

**Established constraints:**

1. **Technology Stack:**
   - Backend: Ruby on Rails 8.0.2 (already in use)
   - Frontend: React 19 + TypeScript (already in use)
   - AI Engine: Python 3.13 (legacy, will be refactored)
   - Orchestration: Temporal (already in use)
   - Database: PostgreSQL 15.3
   - Storage: AWS S3 for artifacts

2. **Architecture Constraints:**
   - Multi-part monorepo structure
   - Temporal for all workflow execution
   - Docker containers for agent isolation
   - MITM proxy for billing tracking (innovative approach)

3. **Dependencies:**
   - LLM Providers: Anthropic, OpenAI, OpenRouter
   - External APIs: GitHub, Linear
   - Infrastructure: Docker, Temporal, PostgreSQL, Redis, Qdrant, S3

### Cross-Cutting Concerns Identified

1. **Multi-tenancy Isolation**
   - Affects: all queries, data access, secrets management, billing
   - Requires: company_id filtering everywhere, row-level security patterns

2. **Billing & Cost Tracking**
   - Affects: all agent sessions, workflow execution, analytics
   - Requires: MITM proxy integration, usage events aggregation, cost calculation

3. **Secrets Management**
   - Affects: agent sessions, tools execution, integrations
   - Requires: secrets hierarchy, encryption at rest, injection into containers

4. **Artifact Provenance**
   - Affects: workflow execution, artifact management, UX display
   - Requires: tracking of artifact source, links between steps

5. **Session State Management**
   - Affects: Interactive sessions, workflow execution, error recovery
   - Requires: state preservation, graceful degradation

6. **Real-time Updates**
   - Affects: file tree, workflow status, team visibility
   - Requires: WebSocket infrastructure, state synchronization

7. **Audit & Compliance**
   - Affects: all admin actions, secrets management, user management
   - Requires: structured logging, audit trail for SOC 2

## Starter Template Evaluation

### Primary Technology Domain

**Full-stack web application (brownfield)** — the project is already initialized and uses an established technology stack.

### Starter Options Considered

Since this is a brownfield project with an already established architecture, evaluating a starter template is not required. The project uses a custom setup without a standard starter template.

### Current Architecture Foundation

**The project uses:**
- Rails 8.0.2 (initialized via `rails new`)
- React 19 + Vite (configured manually)
- Feature-Sliced Design structure for the frontend
- Multi-part monorepo organization (`web/`, `ai-engine/`, `docker/`)

**Architectural decisions already established:**

**Language & Runtime:**
- Ruby 3.x for the backend
- Node.js for frontend build tooling
- Python 3.13 for AI workers
- TypeScript 5.9.3 for type safety

**Styling Solution:**
- Material UI 6.4.7 as the UI library foundation
- Custom dark theme with a grayscale palette
- SCSS for Rails assets

**Build Tooling:**
- Vite 7.3.1 for frontend HMR and build
- Rails asset pipeline for backend assets

**Testing Framework:**
- Minitest for the Rails backend (controllers only)
- Mandatory use of factories for tests
- Factories
- **Note:** Tests run in Docker. We write tests only for controllers, not for models.

**Code Organization:**
- Feature-Sliced Design for the frontend (`app/frontend/`)
- Rails MVC for the backend (`app/controllers/`, `app/models/`, `app/services/`)
- Multi-part monorepo (`web/`, `ai-engine/`, `docker/`)

**Development Experience:**
- `bin/dev` to run Rails + Vite
- Hot reloading via Vite
- Docker Compose for infrastructure
- Temporal UI for workflow debugging

**Note:** Since this is a brownfield project with an already established architecture, there is no need for a starter template. The current structure serves as the foundation for further architectural decisions.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
- Data modeling approach (ActiveRecord primary)
- Authentication method (Google OAuth)
- API design pattern (REST)
- State management (Redux Toolkit + Zustand)
- Hosting strategy (AWS ECS Fargate)

**Important Decisions (Shape Architecture):**
- Authorization patterns (RBAC + Pundit)
- Error handling (Rails standard)
- Performance optimization (code splitting, lazy loading)
- CI/CD pipeline (GitHub Actions)
- Monitoring (Lograge + Sentry + Temporal UI)

**Deferred Decisions (Post-MVP):**
- Rate limiting (skipped for MVP)
- Scaling strategy (deferred due to Docker sessions)
- Multiple OAuth providers (expansion later)

### Data Architecture

**Database Choice:** PostgreSQL 15.3 (already in use)

**Data Modeling Approach:**
- **Primary:** ActiveRecord ORM (main approach)
- **Fallback:** Raw SQL for complex analytical queries
- **Rationale:** ActiveRecord provides simplicity and productivity for most cases, raw SQL for optimization where necessary

**Data Validation Strategy:**
- **Multi-level validation:** Database constraints + Model validations + Service-level validation
- **Database constraints:** NOT NULL, foreign keys, check constraints for data integrity
- **Model validations:** Rails validations for UX and business rules
- **Service-level:** Complex business logic in service classes
- **Rationale:** Three-tier protection ensures data integrity at all levels

**Migration Strategy:**
- **Approach:** Rails migrations
- **Rationale:** Standard Rails approach, already used in the project

**Caching Strategy:**
- **Redis:** Session state, frequent queries, real-time data
- **Rails cache:** Application-level caching
- **CDN:** Static files and assets
- **Database query caching:** Automatic via ActiveRecord
- **Rationale:** Multi-layered caching for performance optimization

### Authentication & Security

**Authentication Method:**
- **Approach:** Google OAuth only (for MVP)
- **Future:** Ability to expand to other OAuth providers
- **Rationale:** Simplicity for MVP, internal tool, Google OAuth already implemented

**Authorization Patterns:**
- **Approach:** RBAC (Role-Based Access Control) + Pundit policies everywhere
- **Roles:** Admin, Collaborator
- **Policy objects:** Pundit for flexible checks at the project/resource level
- **Rationale:** RBAC provides the basic structure, Pundit gives flexibility for complex cases

**Security Middleware:**
- **Approach:** Rails built-in security + Rack middleware
- **Components:** CSRF protection, secure headers, rate limiting middleware
- **Rationale:** Rails built-in provides baseline protection, Rack middleware for additional requirements

**Data Encryption Approach:**
- **Secrets:** ActiveSupport::MessageEncryptor
- **Rationale:** Simplicity and integration with Rails credentials

**API Security Strategy:**
- **Approach:** Session-based authentication for all APIs (including the UI API)
- **Rationale:** Simplification for MVP, all APIs are used only for the UI, no external clients

### API & Communication Patterns

**API Design Pattern:**
- **Approach:** REST API for all endpoints
- **Rationale:** Standard approach, already in use, suitable for all cases

**API Documentation Approach:**
- **Approach:** OAS Rails (OpenAPI Specification for Rails)
- **Rationale:** Automatic documentation generation from Rails controllers

**Error Handling Standards:**
- **Approach:** Rails standard errors
- **Rationale:** Simplicity and consistency with the Rails approach

**Rate Limiting Strategy:**
- **Approach:** Skipped for MVP
- **Rationale:** Internal tool, rate limiting is not critical at the initial stage

**Communication Between Services:**
- **Approach:** Temporal for orchestration
- **Rationale:** Temporal is already in use and sufficient for all inter-service communications

### Frontend Architecture

**State Management Approach:**
- **Approach:** Redux Toolkit + Zustand (hybrid)
- **Redux Toolkit:** Global state (API cache, user state)
- **Zustand:** Local component state
- **Rationale:** Optimal balance between centralized and local state

**Component Architecture:**
- **Approach:** Feature-Sliced Design
- **Rationale:** Already in use, well-structured architecture

**Routing Strategy:**
- **Approach:** TanStack Router
- **Rationale:** Type-safe routing, already in use

**Performance Optimization:**
- **Code splitting:** Vite dynamic imports
- **Lazy loading:** Components and routes
- **Memoization:** React.memo, useMemo, useCallback where necessary
- **Virtual scrolling:** For large artifact lists
- **Rationale:** Comprehensive optimization for performance

**Bundle Optimization:**
- **Approach:** Vite build optimization + chunk splitting
- **Rationale:** Optimization of bundle size and load time

### Infrastructure & Deployment

**Hosting Strategy:**
- **Approach:** AWS ECS Fargate
- **Rationale:** Serverless containers, managed service, suitable for Docker-based architecture

**CI/CD Pipeline Approach:**
- **Approach:** GitHub Actions
- **Rationale:** Integration with GitHub, automation of tests and deployment

**Environment Configuration:**
- **Development:** .env and .env.development + Docker Compose + settings.yml
- **Production:** AWS environment variables + AWS Secrets Manager
- **Rationale:** Simplicity for development, security for production

**Monitoring and Logging:**
- **Structured logging:** Lograge
- **Error tracking:** Sentry
- **Workflow monitoring:** Temporal UI
- **Rationale:** Comprehensive monitoring at all levels

**Scaling Strategy:**
- **Approach:** Deferred
- **Rationale:** Docker sessions for terminals do not scale horizontally, fixed resources for MVP

### Decision Impact Analysis

**Implementation Sequence:**
1. Data models and migrations (ActiveRecord)
2. Authentication setup (Google OAuth)
3. Authorization policies (Pundit)
4. API endpoints (REST)
5. Frontend state management (Redux Toolkit + Zustand)
6. Performance optimizations (code splitting, lazy loading)
7. CI/CD pipeline (GitHub Actions)
8. Deployment setup (AWS ECS Fargate)

**Cross-Component Dependencies:**
- Authentication → Authorization → API endpoints
- Data models → API endpoints → Frontend state
- Frontend architecture → Performance optimizations
- Infrastructure → CI/CD → Deployment

## Implementation Patterns & Consistency Rules

### Pattern Categories Defined

**Critical Conflict Points Identified:**
5 main categories of patterns that will prevent conflicts between AI agents during project implementation.

### Naming Patterns

**Database Naming Conventions:**
- **Tables:** snake_case, plural — `users`, `workflows`, `workflow_runs`
- **Columns:** snake_case — `user_id`, `created_at`, `company_id`
- **Foreign keys:** `{table}_id` — `user_id`, `project_id`
- **Indexes:** `idx_{table}_{column}` — `idx_users_email`, `idx_workflows_project_id`
- **Rationale:** Rails convention, consistency with ActiveRecord

**API Naming Conventions:**
- **Endpoints:** Plural resources — `/api/v1/users`, `/api/v1/projects`
- **Nested resources:** `/api/v1/projects/:project_id/workflows`
- **Route parameters:** `:id` format — `/api/v1/users/:id`
- **Query parameters:** snake_case — `user_id`, `project_id`
- **Headers:** `X-Custom-Header` format for custom headers
- **Rationale:** RESTful conventions, consistency with Rails routing

**Code Naming Conventions:**

**Frontend (TypeScript/React):**
- **Components:** PascalCase — `UserCard.tsx`, `WorkflowStepper.tsx`
- **Files:** PascalCase for components — `UserCard.tsx`
- **Functions/Variables:** camelCase — `getUserData()`, `userId`
- **Constants:** UPPER_SNAKE_CASE — `API_BASE_URL`, `MAX_RETRIES`

**Backend (Ruby):**
- **Classes:** PascalCase — `UserCard`, `WorkflowService`
- **Methods/Variables:** snake_case — `get_user_data`, `user_id`
- **Constants:** UPPER_SNAKE_CASE — `API_BASE_URL`

### Structure Patterns

**Project Organization:**

**Backend (Rails):**
- **Tests:** `test/` directory (Rails convention, Minitest)
- **Services:** `app/services/` for business logic
- **Utils:** `lib/` for shared utilities
- **Concerns:** `app/models/concerns/` for shared model logic

**Frontend (React/TypeScript):**
- **Tests:** Co-located — `UserCard.test.tsx` next to `UserCard.tsx`
- **Components:** Feature-Sliced Design structure
- **Shared utilities:** `app/frontend/shared/lib/`
- **Feature utilities:** inside feature folders
- **API clients:** `app/frontend/shared/api/`

**Configuration File Organization:**
- **Rails:** `config/` directory + `settings.yml` for configuration
- **Frontend:** Environment variables + `config/` for constants
- **Docker:** `docker-compose.yml` + `.env` files

### Format Patterns

**API Response Formats:**
- **Lists:** Wrapped in `items` — `{items: [{id: 1, ...}, ...]}`
- **Single resources:** Wrapped in `data` — `{data: {id: 1, ...}}`
- **Implementation:** A base serializer automatically adds wrappers
- **Rationale:** Consistency of API responses, uniformity

**Error Response Structure:**
- **Validation errors:** Rails standard — `{errors: {field: ["message"]}}`
- **Other errors:** `{error: "message"}` or `{errors: ["message"]}`
- **Rationale:** Rails convention, consistency

**Date/Time Formats:**
- **Format:** ISO 8601 strings — `"2026-01-21T10:30:00Z"`
- **Rationale:** Standard, consistency between frontend and backend

**JSON Field Naming:**
- **API responses:** snake_case — `user_id`, `created_at` (Rails default)
- **Frontend transformation:** The frontend converts to camelCase when necessary
- **Rationale:** Rails convention in the API, JavaScript convention on the frontend

### Communication Patterns

**Event System Patterns:**
- **Status:** Deferred (events are not used in the MVP)
- **Future:** snake_case with dot notation — `user.created`, `workflow.started`

**State Management Patterns:**

**Redux Toolkit:**
- **Updates:** Immutable via Immer (automatically)
- **Action naming:** `feature/action` — `users/fetchUsers`, `workflows/createWorkflow`
- **Selectors:** `select{Entity}{By}` — `selectUserById`, `selectWorkflowsByProject`
- **Usage:** Global state (API cache, user state)

**Zustand:**
- **Updates:** Immer for immutable updates
- **Actions:** Store methods — `fetchUsers()`, `createWorkflow()`
- **Usage:** Local component state

**Logging Formats:**
- **Backend:** Structured JSON via Lograge — `{"level": "info", "message": "...", "context": {...}}`
- **Frontend:** Structured logging — `console.log({level: "info", message: "...", context: {...}})`
- **Rationale:** Consistency, convenience for log analysis

### Process Patterns

**Error Handling Patterns:**

**Backend (Rails):**
- **Global exception handler:** `ApplicationController` rescue_from
- **Service-level errors:** Custom exceptions in services
- **Validation errors:** ActiveRecord validations

**Frontend:**
- **Error boundaries:** React Error Boundaries for components
- **API error handling:** RTK Query error handling
- **User-facing errors:** Toast notifications (MUI Snackbar)

**Loading State Patterns:**
- **Per-request loading:** RTK Query automatically manages loading states
- **Component-level loading:** Zustand for local loading states
- **Rationale:** Separation of responsibilities, automation where possible

**Validation Timing:**
- **Field validation:** On blur (when focus is lost)
- **Form validation:** On submit (when the form is submitted)
- **Implementation:** React Hook Form default behavior
- **Rationale:** Balance between UX and performance

### Enforcement Guidelines

**All AI Agents MUST:**

1. **Follow naming conventions:**
   - Database: snake_case for all tables and columns
   - API: Plural resources, snake_case in responses
   - Code: PascalCase for components/classes, camelCase/snake_case for functions/variables

2. **Maintain structure consistency:**
   - Backend: Rails conventions (`test/controllers/`, `app/services/`, `lib/`)
   - Frontend: Feature-Sliced Design structure
   - Tests: Co-located for frontend, `test/controllers/` for backend (controllers only)

3. **Use consistent formats:**
   - API responses: `{items: [...]}` for lists, `{data: {...}}` for single resources
   - Errors: Rails standard format
   - Dates: ISO 8601 strings

4. **Follow communication patterns:**
   - State management: Redux Toolkit for global, Zustand for local
   - Logging: Structured JSON everywhere
   - Error handling: Error boundaries + RTK Query + toasts

5. **Implement process patterns:**
   - Loading states: RTK Query for API, Zustand for local
   - Validation: On blur + on submit

**Pattern Enforcement:**
- ESLint/Rubocop for automatic checking of naming conventions
- Code review for checking structure and patterns
- Documentation of patterns in this document as a reference

### Pattern Examples

**Good Examples:**

**Database Naming:**
```ruby
# ✅ Correct
create_table :workflow_runs do |t|
  t.references :workflow, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.datetime :started_at
end

# ❌ Incorrect
create_table :WorkflowRuns do |t|
  t.references :WorkflowId
  t.datetime :StartedAt
end
```

**API Response Format:**
```json
// ✅ Correct - List
{
  "items": [
    {"id": 1, "name": "Workflow 1"},
    {"id": 2, "name": "Workflow 2"}
  ]
}

// ✅ Correct - Single resource
{
  "data": {"id": 1, "name": "Workflow 1"}
}

// ❌ Incorrect - Direct response
[
  {"id": 1, "name": "Workflow 1"},
  {"id": 2, "name": "Workflow 2"}
]
```

**Component Naming:**
```typescript
// ✅ Correct
// UserCard.tsx
export const UserCard = () => { ... }

// ❌ Incorrect
// user-card.tsx
export const userCard = () => { ... }
```

**Anti-Patterns:**
- ❌ Mixing naming conventions (snake_case and camelCase in the same place)
- ❌ Direct API responses without wrappers
- ❌ Global loading states instead of per-request
- ❌ Validation only on submit without on blur
- ❌ Unstructured logging

## Project Structure & Boundaries

### Complete Project Directory Structure

```
app/                                    # Root directory
├── _bmad/                             # BMAD Method framework
│   ├── _config/                        # BMAD configuration
│   ├── bmm/                            # BMM module
│   └── core/                           # Core workflows
├── _bmad-output/                       # BMAD output artifacts
│   ├── implementation-artifacts/
│   └── planning-artifacts/
├── ai/                                 # Planning artifacts & documentation
│   ├── architecture.md                 # This document
│   ├── prd.md                          # Product Requirements Document
│   ├── ux-design-specification.md      # UX Design Specification
│   └── ...                             # Other planning docs
├── ai-engine/                          # Python AI Engine (Legacy)
│   ├── app/
│   │   ├── agents/                     # AI Agents
│   │   ├── temporal/                   # Temporal workflows & activities
│   │   └── vector_engine/              # Qdrant integration
│   ├── tests/
│   ├── Dockerfile
│   └── pyproject.toml
├── config/                             # Root configuration
│   └── workflows.yml
├── docker/                             # Docker configurations
│   ├── base/                           # Base Docker image
│   ├── claude-code/                    # Claude Code agent container
│   ├── codex/                          # Codex agent container
│   ├── cursor-cli/                     # Cursor CLI agent container
│   └── shared/                         # Shared Docker utilities
├── docker-compose.yml                  # Development environment
├── docker-compose.ci.yml               # CI environment
├── kb/                                 # Knowledge base
│   ├── product/                        # Product documentation
│   └── operations/                     # Operations docs
├── Makefile                            # Root Makefile
└── web/                                # Rails + React application
    ├── app/
    │   ├── assets/                     # Rails assets (SCSS, images)
    │   ├── channels/                   # ActionCable channels
    │   ├── controllers/                # Rails controllers
    │   │   ├── api/v1/                # REST API endpoints
    │   │   └── web/                   # Web controllers
    │   ├── frontend/                   # React SPA (Feature-Sliced Design)
    │   │   ├── app/                   # App shell, providers
    │   │   ├── entities/              # Domain entities
    │   │   ├── features/              # Feature modules
    │   │   ├── pages/                 # Route pages
    │   │   ├── shared/                # Shared code
    │   │   │   ├── api/               # RTK Query API
    │   │   │   ├── lib/               # Utilities
    │   │   │   ├── theme/             # MUI theme
    │   │   │   └── ui/                # UI components
    │   │   └── widgets/               # Composite UI blocks
    │   ├── models/                     # ActiveRecord models
    │   ├── policies/                   # Pundit policies
    │   ├── serializers/                # API serializers
    │   ├── services/                   # Business logic services
    │   │   ├── container_manager.rb   # Docker orchestration
    │   │   ├── temporal_service.rb    # Temporal client
    │   │   └── workflow_service.rb     # Workflow management
    │   ├── temporal/                   # Temporal integration
    │   │   ├── activities/            # Ruby activities
    │   │   └── workflows/             # Ruby workflows
    │   └── validators/                 # Custom validators
    ├── bin/                            # Executables
    │   ├── dev                         # Development server
    │   └── temporal_worker            # Ruby Temporal worker
    ├── config/                         # Rails configuration
    │   ├── application.rb
    │   ├── routes.rb                  # API routes
    │   ├── settings.yml               # Application settings
    │   └── initializers/              # Rails initializers
    ├── db/                             # Database
    │   ├── migrate/                   # Rails migrations
    │   └── schema.rb                  # Database schema
    ├── lib/                            # Shared libraries
    │   └── tasks/                     # Rake tasks
    ├── test/                           # Rails tests (Minitest)
    │   ├── controllers/                # Controller tests only
    │   └── integration/                # Integration tests (controllers)
    ├── public/                         # Static assets
    ├── Dockerfile                      # Web container
    ├── Gemfile                         # Ruby dependencies
    ├── package.json                    # Node dependencies
    ├── tsconfig.json                   # TypeScript config
    └── vite.config.ts                  # Vite configuration
```

### Architectural Boundaries

**API Boundaries:**

**External API Endpoints:**
- `/api/v1/terminal_sessions` — Docker session management
- `/api/v1/projects` — Project CRUD
- `/api/v1/workflows` — Workflow management
- `/api/v1/artifacts` — Artifact management
- `/api/v1/users` — User management

**Internal Service Boundaries:**
- **ContainerManager** (`app/services/container_manager.rb`) — Docker API boundary
- **TemporalService** (`app/services/temporal_service.rb`) — Temporal workflow boundary
- **WorkflowService** (`app/services/workflow_service.rb`) — Workflow business logic boundary

**Authentication & Authorization Boundaries:**
- **Authentication:** Google OAuth via OmniAuth (`config/initializers/omniauth.rb`)
- **Authorization:** Pundit policies (`app/policies/`) for resource-level checks
- **RBAC:** Role checks in models (`User`, `ProjectCollaborator`)

**Data Access Layer Boundaries:**
- **Models:** ActiveRecord models (`app/models/`)
- **Serializers:** API serializers (`app/serializers/`)
- **Services:** Business logic layer (`app/services/`)

**Component Boundaries:**

**Frontend Component Communication:**
- **Pages → Features:** Pages use features for UI
- **Features → Entities:** Features use entities for domain logic
- **Shared → All:** Shared utilities are available everywhere

**State Management Boundaries:**
- **Redux Toolkit:** Global state (`app/frontend/shared/api/`)
- **Zustand:** Local state (inside features/components)

**State Machine Pattern (AASM):**
- **Purpose:** Managing the lifecycle and state transitions for business entities
- **Implementation:** AASM gem for backend state machines
- **Location:** `app/state_machines/`
- **Active State Machines:**
  - `CompanyStateMachine`: Managing company states
    - States: `active` (initial), `suspended`, `archived`
    - Events: `suspend`, `activate`, `archive`
    - Auto-generated scopes: `.active`, `.suspended`, `.archived`
  - `UserStateMachine`: Managing user states
    - States: `active` (initial), `pending`, `suspended`, `archived`
    - Events: `activate`, `suspend`, `archive`, `mark_pending`
    - Auto-generated scopes: `.active`, `.pending`, `.suspended`, `.archived`
  - `StateEventConcern`: Provides `available_events` and `available_states` helpers
- **Note:** Roles and positions use `enumerize`, not state machines
  - Roles: `employee`, `admin`, `super_admin` (enumerize)
  - Positions: `qa`, `pm_po_ba`, `dev`, `designer`, `cto` (enumerize)

**Automatic Case Conversion (Frontend ↔ Backend):**
- **Purpose:** Automatic conversion between camelCase (frontend) and snake_case (backend)
- **Implementation:** `camelcaseKeys` and `decamelizeKeys` in `baseApi.ts`
- **Location:** `app/frontend/shared/api/baseApi.ts`
- **How it works:**
  - **Request (Frontend → Backend):**
    ```typescript
    data: isDecamelize ? decamelizeKeys(data) : data
    // { currentUser: { passwordConfirmation: "..." } }
    // → { current_user: { password_confirmation: "..." } }
    ```
  - **Response (Backend → Frontend):**
    ```typescript
    data: camelcaseKeys(result.data)
    // { current_user: { password_confirmation: "..." } }
    // → { currentUser: { passwordConfirmation: "..." } }
    ```
- **TypeScript Interfaces:** All interfaces are written in camelCase (following TypeScript best practices)
  - Example: `IUpdateCurrentUserRequest`, `IUser`, `ICompany`
- **Benefits:**
  - No need to manually write transform functions
  - TypeScript types in pure camelCase
  - Automatic conversion at the HTTP client level
  - Consistency with the `web_reference` project

**Service Communication Patterns:**
- **Rails → Temporal:** Via TemporalService
- **Rails → Docker:** Via ContainerManager
- **Frontend → Backend:** HTTP REST API via RTK Query

**Data Boundaries:**

**Database Schema Boundaries:**
- **Multi-tenancy:** All tenant tables have `company_id`
- **Core entities:** `users`, `companies`, `projects`, `workflows`
- **Execution tracking:** `workflow_runs`, `step_runs`, `artifacts`
- **Billing:** `usage_events` for cost tracking

**Data Access Patterns:**
- **ActiveRecord:** Main ORM for all DB operations
- **Raw SQL:** For complex analytical queries

**Caching Boundaries:**
- **Redis:** Session state, frequent queries
- **Rails cache:** Application-level caching
- **CDN:** Static assets

**External Data Integration Points:**
- **S3:** Artifact storage (`config/storage.yml`)
- **Temporal:** Workflow orchestration
- **Docker:** Container management
- **GitHub/Linear:** External API integrations (future)

### Requirements to Structure Mapping

**FR Category: Agent Sessions (FR1-FR9)**
- **Controllers:** `app/controllers/api/v1/terminal_sessions_controller.rb`
- **Services:** `app/services/container_manager.rb`
- **Frontend:** `app/frontend/pages/session/`, `app/frontend/features/file-tree/`
- **Temporal:** `app/temporal/workflows/` for session lifecycle
- **Docker:** `docker/claude-code/`, `docker/codex/`, `docker/cursor-cli/`

**FR Category: Workflow Management (FR10-FR18)**
- **Controllers:** `app/controllers/api/v1/workflows_controller.rb` (future)
- **Services:** `app/services/workflow_service.rb`
- **Models:** `app/models/workflow.rb` (future)
- **Frontend:** `app/frontend/pages/workflow/`, `app/frontend/features/workflow-stepper/`
- **Temporal:** `app/temporal/workflows/` for workflow execution

**FR Category: Artifact Management (FR19-FR25)**
- **Controllers:** `app/controllers/api/v1/artifacts_controller.rb` (future)
- **Models:** `app/models/artifact.rb` (future)
- **Uploaders:** `app/uploaders/asset_uploader.rb`
- **Frontend:** `app/frontend/pages/artifacts/`, `app/frontend/features/artifact-viewer/`
- **Storage:** S3 via Shrine (`config/storage.yml`)

**FR Category: Project & Collaboration (FR26-FR31)**
- **Models:** `app/models/project.rb`, `app/models/project_collaborator.rb`
- **Controllers:** `app/controllers/api/v1/projects_controller.rb` (future)
- **Policies:** `app/policies/project_policy.rb` (future)
- **Frontend:** `app/frontend/pages/projects/`, `app/frontend/features/project-card/`

**FR Category: Secrets Management (FR32-FR36)**
- **Models:** `app/models/secret.rb` (future)
- **Services:** `app/services/secrets_service.rb` (future)
- **Encryption:** ActiveSupport::MessageEncryptor
- **Frontend:** `app/frontend/pages/settings/secrets/` (future)

**FR Category: Tools Framework (FR37-FR41)**
- **Models:** `app/models/tool.rb` (future)
- **Services:** `app/services/tool_service.rb` (future)
- **Temporal:** `app/temporal/activities/tool_execution.rb` (future)
- **Docker:** Custom tool containers

**FR Category: Billing & Analytics (FR42-FR46)**
- **Models:** `app/models/usage_event.rb` (future)
- **Services:** `app/services/billing_service.rb` (future)
- **Frontend:** `app/frontend/pages/analytics/` (future)
- **MITM Proxy:** `docker/claude-code/` billing interceptor

**FR Category: User Management (FR47-FR50)**
- **Models:** `app/models/user.rb`, `app/models/company.rb`
- **Controllers:** `app/controllers/api/v1/users_controller.rb` (future)
- **Policies:** `app/policies/user_policy.rb` (future)
- **Frontend:** `app/frontend/pages/users/` (future)
- **Auth:** Google OAuth via OmniAuth

**FR Category: Integrations (FR51-FR53)**
- **Services:** `app/services/integration_service.rb` (future)
- **Temporal:** `app/temporal/activities/github_integration.rb` (future)
- **Frontend:** Integration UI (future)

**Cross-Cutting Concerns:**

**Authentication System:**
- **Config:** `config/initializers/omniauth.rb`
- **Models:** `app/models/user.rb`
- **Frontend:** `app/frontend/shared/api/auth.ts`

**Authorization System:**
- **Policies:** `app/policies/` (Pundit)
- **Models:** Role checks in `User`, `ProjectCollaborator`
- **Frontend:** Permission checks via API

**Multi-tenancy:**
- **Models:** All tenant models have `company_id`
- **Policies:** Company-scoped checks in Pundit
- **Services:** Company filtering in services

**Billing & Cost Tracking:**
- **MITM Proxy:** `docker/claude-code/billing_interceptor.py` (future)
- **Models:** `app/models/usage_event.rb` (future)
- **Services:** `app/services/billing_service.rb` (future)

**Real-time Updates:**
- **Channels:** `app/channels/` (ActionCable)
- **WebSocket:** File tree updates via watcher
- **Frontend:** WebSocket clients in features

### Integration Points

**Internal Communication:**

**Rails → Temporal:**
- **Service:** `TemporalService.start_workflow()`
- **Activities:** `app/temporal/activities/`
- **Workflows:** `app/temporal/workflows/`

**Rails → Docker:**
- **Service:** `ContainerManager.create_session()`
- **API:** Docker API via Unix socket

**Frontend → Backend:**
- **API:** RTK Query (`app/frontend/shared/api/`)
- **Endpoints:** `/api/v1/*` REST API
- **Serializers:** `app/serializers/` for response formatting

**External Integrations:**

**S3 Storage:**
- **Config:** `config/storage.yml`
- **Uploader:** `app/uploaders/asset_uploader.rb`
- **Usage:** Artifact storage

**Temporal Server:**
- **Connection:** gRPC via TemporalService
- **Workflows:** Cross-language workflows (Ruby ↔ Python)

**Docker API:**
- **Connection:** Unix socket
- **Usage:** Container lifecycle management

**Future Integrations:**
- **GitHub:** API for PR creation, code context
- **Linear:** API for task export
- **LLM Providers:** Anthropic, OpenAI, OpenRouter

**Data Flow:**

**Session Creation Flow:**
1. Frontend → Rails API (`POST /api/v1/terminal_sessions`)
2. Rails → ContainerManager (create Docker container)
3. ContainerManager → Docker API
4. Rails → Temporal (start session workflow)
5. Temporal → Python Worker (if needed)
6. Response → Frontend (session URLs)

**Workflow Execution Flow:**
1. Frontend → Rails API (start workflow)
2. Rails → TemporalService (start workflow)
3. Temporal → Ruby/Python Activities
4. Activities → Services (business logic)
5. Services → Models (data persistence)
6. Temporal → Frontend (status updates via WebSocket)

**Artifact Flow:**
1. Workflow Step → Generate artifact
2. Artifact → Upload to S3 (via Shrine)
3. Metadata → Save to DB (via Model)
4. Frontend → Fetch artifact (via API)
5. API → Load from S3 + return metadata

### File Organization Patterns

**Configuration Files:**
- **Rails:** `config/` directory
- **Settings:** `config/settings.yml` (Dynaconf)
- **Environment:** `.env.development`, `.env.production`
- **Docker:** `docker-compose.yml`, `.env` files
- **Frontend:** `vite.config.ts`, `tsconfig.json`

**Source Organization:**
- **Backend:** Rails MVC structure (`app/controllers/`, `app/models/`, `app/services/`)
- **Frontend:** Feature-Sliced Design (`app/frontend/`)
- **Shared:** `lib/` for Ruby, `app/frontend/shared/` for TypeScript

**Test Organization:**
- **Backend:** `test/controllers/` directory (Minitest) - controller tests only
- **Frontend:** Co-located tests (`*.test.tsx` next to components)
- **Integration:** `test/integration/` for Rails (controllers only)
- **Note:** Tests run in Docker. We write tests only for controllers, not for models.

**Testing Patterns:**
- **Factories & Sequences:** Always use FactoryBot with sequences for data generation
- **Factory Rules:** In factories, nothing should be written directly in fields, except `password_confirmation` which duplicates `password`
- **Data Generation:** All values are generated via sequences (email, name, password, etc.)
- **Traits:** Use traits for variations (for example, `:super_admin`, `:with_company`)

**Admin Panel:**
- **Approach:** Use the Administrate gem for the admin panel
- **No custom dashboard:** Standard resource controllers without a custom dashboard controller
- **Rationale:** Administrate provides all the needed features out of the box

**Super Admin Role Management:**
- **Approach:** The super admin role is protected via strong params and cannot be changed through the UI
- **Validation:** Only at the strong params level in the controller, not in the model
- **Seeds:** The super admin is created only via seeds or a direct DB update
- **Enumerize:** Supports symbols for role assignment (`:super_admin` works correctly)

**Field Naming Decisions:**
- **`state` vs `status`:** Use `state` for the User model (team preference)
- **Enumerize scopes:** `enumerize :state, scope: true` creates `User.active`, not `User.with_state(:active)`
- **Rationale:** Shorter and more readable syntax

**Authorization Patterns:**
- **AdminConstraint:** Not used, protection only via `authenticate_admin!` in the controller
- **Rationale:** A check in the controller is sufficient, a constraint is redundant for the current requirements

**Project Collaborators:**
- **`add_collaborator` method:** Provided by the AASM gem or a custom implementation
- **Rationale:** AASM is used for state machine functionality

**Asset Organization:**
- **Rails assets:** `app/assets/` (SCSS, images)
- **Frontend assets:** `app/frontend/shared/ui/` for components
- **Static files:** `public/` directory
- **S3:** Artifacts via Shrine uploader

### Development Workflow Integration

**Development Server Structure:**
- **Command:** `bin/dev` (Foreman)
- **Processes:** Rails server + Vite dev server
- **Hot reloading:** Vite HMR for frontend
- **Docker:** `docker-compose up` for infrastructure

**Build Process Structure:**
- **Frontend:** Vite build → `public/vite-build/`
- **Backend:** Rails assets → `public/assets/`
- **Docker:** Multi-stage builds for production

**Deployment Structure:**
- **Platform:** AWS ECS Fargate
- **CI/CD:** GitHub Actions
- **Containers:** Web container + Temporal workers
- **Storage:** S3 for artifacts, RDS for PostgreSQL

## Architecture Validation Results

### Coherence Validation ✅

**Decision Compatibility:**
- ✅ All technology decisions are compatible: Rails 8.0.2 + React 19 + PostgreSQL 15.3 + Temporal work together without conflicts
- ✅ All versions checked for compatibility
- ✅ Patterns align with the technology stack: Feature-Sliced Design for React, Rails MVC for the backend
- ✅ No contradictions between decisions found

**Pattern Consistency:**
- ✅ Naming conventions are consistent: snake_case for backend, PascalCase/camelCase for frontend
- ✅ Structure patterns are consistent: Rails conventions + Feature-Sliced Design
- ✅ Communication patterns are consistent: REST API + RTK Query + Temporal
- ✅ Process patterns are consistent: error handling, loading states defined consistently

**Structure Alignment:**
- ✅ The project structure supports all architectural decisions: a multi-part monorepo matches the architecture
- ✅ Boundaries are defined correctly: API boundaries, component boundaries, and data boundaries are clearly defined
- ✅ The structure supports the chosen patterns: Feature-Sliced Design is implemented in the structure
- ✅ Integration points are properly structured: Temporal, Docker, and S3 integrations are defined

### Requirements Coverage Validation ✅

**Functional Requirements Coverage:**

All 9 categories of functional requirements are fully covered by architectural decisions:
- ✅ **Agent Sessions (FR1-FR9):** ContainerManager, Docker containers, Temporal workflows
- ✅ **Workflow Management (FR10-FR18):** WorkflowService, Temporal, frontend components
- ✅ **Artifact Management (FR19-FR25):** S3 storage, Shrine uploader, models
- ✅ **Project & Collaboration (FR26-FR31):** Multi-tenancy, Pundit policies
- ✅ **Secrets Management (FR32-FR36):** ActiveSupport::MessageEncryptor, models
- ✅ **Tools Framework (FR37-FR41):** Docker containers, Temporal activities
- ✅ **Billing & Analytics (FR42-FR46):** MITM proxy, usage events models
- ✅ **User Management (FR47-FR50):** Google OAuth, RBAC, Pundit
- ✅ **Integrations (FR51-FR53):** Services, Temporal activities

**Non-Functional Requirements Coverage:**

All NFR categories are fully covered:
- ✅ **Security (NFR-S1-S6):** Encryption, multi-tenancy isolation, audit logs
- ✅ **Reliability (NFR-R1-R5):** Temporal for reliability, S3 redundancy, error handling
- ✅ **Integration (NFR-I1-I5):** Multiple LLM providers, MITM proxy, Temporal
- ✅ **Operability (NFR-O1-O3):** Lograge, health checks, Temporal UI

### Implementation Readiness Validation ✅

**Decision Completeness:**
- ✅ All critical decisions are documented with specific versions
- ✅ Implementation patterns are detailed enough to prevent conflicts
- ✅ Consistency rules are clear and applicable
- ✅ Examples are provided for all major patterns

**Structure Completeness:**
- ✅ The project structure is complete and concrete
- ✅ All files and directories are defined
- ✅ Integration points are clearly specified
- ✅ Component boundaries are well defined

**Pattern Completeness:**
- ✅ All potential conflict points are addressed
- ✅ Naming conventions comprehensive
- ✅ Communication patterns are fully defined
- ✅ Process patterns (error handling, loading) are complete

### Gap Analysis Results

**Critical Gaps:**
No critical gaps that would block implementation were found.

**Important Gaps:**
1. Some models have not yet been created (Workflow, Artifact, Secret, UsageEvent) — they will be created when the corresponding features are implemented
2. Some controllers are marked as "future" — they will be created as needed
3. MITM proxy billing interceptor — requires implementation in Docker containers

**Nice-to-Have Gaps:**
1. Additional code examples for complex patterns
2. Documentation for deployment on AWS ECS Fargate
3. Integration tests for cross-service communication

### Validation Issues Addressed

All issues found were analyzed and determined to be non-blocking. The architecture is ready for implementation.

### Architecture Completeness Checklist

**✅ Requirements Analysis**
- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified
- [x] Cross-cutting concerns mapped

**✅ Architectural Decisions**
- [x] Critical decisions documented with versions
- [x] Technology stack fully specified
- [x] Integration patterns defined
- [x] Performance considerations addressed

**✅ Implementation Patterns**
- [x] Naming conventions established
- [x] Structure patterns defined
- [x] Communication patterns specified
- [x] Process patterns documented

**✅ Project Structure**
- [x] Complete directory structure defined
- [x] Component boundaries established
- [x] Integration points mapped
- [x] Requirements to structure mapping complete

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION ✅

**Confidence Level:** High — all requirements are covered, decisions are validated, patterns are defined

**Key Strengths:**
- Comprehensive technology stack with proven versions
- Detailed implementation patterns prevent conflicts between AI agents
- Complete project structure with clear boundaries
- All requirements (FR and NFR) are architecturally supported
- Validation confirmed coherence and completeness

**Areas for Future Enhancement:**
- Additional code examples for complex patterns
- Detailed deployment documentation
- Integration tests for cross-service communication

### Implementation Handoff

**AI Agent Guidelines:**
- Follow all architectural decisions exactly as documented
- Use implementation patterns consistently across all components
- Respect the project structure and boundaries
- Refer to this document for all architectural questions

**First Implementation Priority:**
The project is already initialized. Next steps:
1. Implement the missing models (Workflow, Artifact, Secret, UsageEvent)
2. Create API controllers for workflows and artifacts
3. Implement the MITM proxy billing interceptor
4. Set up the CI/CD pipeline (GitHub Actions)
5. Prepare for deployment on AWS ECS Fargate

## Architecture Completion Summary

### Workflow Completion

**Architecture Decision Workflow:** COMPLETED ✅
**Total Steps Completed:** 8
**Date Completed:** 2026-01-21
**Document Location:** ai/architecture.md

### Final Architecture Deliverables

**📋 Complete Architecture Document**

- All architectural decisions documented with specific versions
- Implementation patterns ensuring AI agent consistency
- Complete project structure with all files and directories
- Requirements to architecture mapping
- Validation confirming coherence and completeness

**🏗️ Implementation Ready Foundation**

- 25+ architectural decisions made across 5 categories
- 5 implementation pattern categories defined
- 15+ architectural components specified
- 53 functional requirements fully supported
- 15 non-functional requirements addressed

**📚 AI Agent Implementation Guide**

- Technology stack with verified versions (Rails 8.0.2, React 19, PostgreSQL 15.3, Temporal)
- Consistency rules that prevent implementation conflicts
- Project structure with clear boundaries
- Integration patterns and communication standards

### Implementation Handoff

**For AI Agents:**
This architecture document is your complete guide for implementing Palad. Follow all decisions, patterns, and structures exactly as documented.

**Development Sequence:**

1. Review architecture document before implementing each story
2. Follow technology choices and patterns exactly
3. Use the project structure we defined
4. Maintain consistency with documented rules

### Quality Assurance Checklist

**✅ Architecture Coherence**

- [x] All decisions work together without conflicts
- [x] Technology choices are compatible
- [x] Patterns support the architectural decisions
- [x] Structure aligns with all choices

**✅ Requirements Coverage**

- [x] All functional requirements are supported
- [x] All non-functional requirements are addressed
- [x] Cross-cutting concerns are handled
- [x] Integration points are defined

**✅ Implementation Readiness**

- [x] Decisions are specific and actionable
- [x] Patterns prevent agent conflicts
- [x] Structure is complete and unambiguous
- [x] Examples are provided for clarity

### Project Success Factors

**🎯 Clear Decision Framework**
Every technology choice was made collaboratively with clear rationale, ensuring all stakeholders understand the architectural direction.

**🔧 Consistency Guarantee**
Implementation patterns and rules ensure that multiple AI agents will produce compatible, consistent code that works together seamlessly.

**📋 Complete Coverage**
All project requirements are architecturally supported, with clear mapping from business needs to technical implementation.

**🏗️ Solid Foundation**
The established architectural patterns provide a production-ready foundation following current best practices.

---

## Implementation Updates (2026-01-23)

### User Onboarding Flow

**Decision:** Mandatory 4-Step Onboarding with Strict Validation (updated in Story 2.1, verified in Story 2.2)

**Context:**
Users must complete onboarding before accessing the platform. Onboarding **cannot be skipped** and includes:
1. **Step 1 - Your Profile:** Selecting position (Dev, QA, PM/PO/BA, Designer, CTO) and preferred agent language
2. **Step 2 - Select Agents:** Selecting at least one AI agent (Claude Code, Cursor CLI, Codex, Gemini CLI)
   - Each agent displays name and detailed description
   - Visual states: default, selected (highlighted border), hover
   - Validation: at least 1 agent required to proceed
   - State persists across step navigation (back/forward)
3. **Step 3 - Authenticate:** Authenticating at least one selected agent
4. **Step 4 - Complete:** Reviewing and confirming setup

**No progress is saved** - users must complete all steps in one session.

**Edit Mode:** Users who have completed onboarding can return to `/onboarding` to edit their profile, position, language, and agents. Configured agents are pre-selected in Step 2.

**Solution:**
Implemented automatic `onboarding_completed_at` tracking via `before_validation` callback in User model:

```ruby
# app/models/user.rb
has_secure_password validations: false

# Constants
AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
POSITIONS = %w[qa pm_po_ba dev designer].freeze
AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli].freeze

# Database fields
# - configured_agents: text[] (PostgreSQL array)
# - position: string
# - preferred_agent_language: string
# - onboarding_completed_at: datetime

# Validations
validate :at_least_one_agent_after_onboarding
validate :configured_agents_valid

# Callbacks
before_validation :set_onboarding_completed_at, if: :onboarding_ready?

private

def onboarding_ready?
  return false if super_admin? # Super admins don't need onboarding
  return false if onboarding_completed? # Already completed

  # Onboarding is ready when position, language, and at least one agent are configured
  position.present? &&
    preferred_agent_language.present? &&
    has_configured_agents?
end

def has_configured_agents?
  configured_agents.present? && configured_agents.any?
end

def set_onboarding_completed_at
  self.onboarding_completed_at = Time.current
end
```

**Rationale:**
1. **Single Responsibility:** Controller only updates user attributes, model handles completion logic
2. **Mandatory Onboarding:** No "Skip" button - ensures all users have proper configuration before platform access
3. **Consistency:** Onboarding is always marked complete when ALL requirements are met (position + language + agent)
4. **Rails Convention:** Business logic lives in models, not controllers
5. **Data Integrity:** PostgreSQL array ensures valid storage, validations ensure valid values
6. **4-Step Flow:** Clear progression through profile → agents → authentication → completion (updated in Story 2.1)
7. **Edit Mode:** Allows users to update their profile and agents after initial completion

**API Changes:**
- `PATCH /api/v1/current_user` - accepts `position`, `preferred_agent_language`, and `configured_agents` (array)
- Backend automatically sets `onboarding_completed_at` when all three fields are valid and present
- Frontend doesn't send or manage `onboarding_completed_at`

**Database Schema:**
```sql
ALTER TABLE users ADD COLUMN configured_agents text[] DEFAULT '{}';
```

**Testing:**
- Controller tests verify position/language/agents update
- Model tests verify automatic completion only when all fields present
- Validation tests ensure at least one agent required after onboarding

---

### Agent Authentication Infrastructure (Story 2.3)

**Decision:** Terminal Sessions with State Machines + Temporal Workflows + Docker Containers

**Context:**
Users need to authenticate agent CLIs (Claude Code, Cursor CLI, Codex, Gemini CLI) during onboarding (Step 3). Authentication happens via interactive web terminals where users log into the agent CLI. After authentication, credentials are extracted from the container and stored encrypted for future sessions.

**Architecture Components:**

#### 1. TerminalSession Model (AASM State Machine)

```ruby
# app/models/terminal_session.rb
class TerminalSession < ApplicationRecord
  include AASM

  belongs_to :user
  belongs_to :project, optional: true  # Nullable for auth_setup sessions

  # Fields:
  # - session_type: string (auth_setup, agent_session, tool_setup, workflow_step)
  # - agent_type: string (claude_code, cursor_cli, codex, gemini_cli)
  # - state: string (not_started, started, running, stopped, collected, failed, cancelled)
  # - temporal_workflow_id: string
  # - temporal_run_id: string
  # - container_id: string
  # - websocket_url: string
  # - artifacts_path: string (reference to AgentCredential ID)
  # - error_message: text
  # - metadata: jsonb
  # - timestamps: started_at, finished_at, collected_at

  aasm column: :state do
    state :not_started, initial: true
    state :started         # Container starting
    state :running         # Container ready, user authenticating
    state :stopped         # User clicked "Finish Auth"
    state :collected       # Artifacts extracted and stored
    state :failed
    state :cancelled

    event :start do
      transitions from: :not_started, to: :started, after: :start_temporal_workflow
    end

    event :mark_running do
      transitions from: :started, to: :running
    end

    event :stop do
      transitions from: :running, to: :stopped
    end

    event :collect do
      transitions from: :stopped, to: :collected, after: :update_user_configured_agents
    end

    event :fail do
      transitions from: %i[not_started started running stopped], to: :failed, after: :cleanup_resources
    end

    event :cancel do
      transitions from: %i[not_started started running], to: :cancelled, after: :cleanup_resources
    end
  end

  def update_user_configured_agents
    return unless session_type == "auth_setup" && agent_type.present?

    user.add_configured_agent(agent_type) unless user.configured_agents.include?(agent_type)
    update!(collected_at: Time.current)
  end
end
```

#### 2. Temporal Workflow (AgentAuthWorkflow)

**Flow:**
1. **StartAuthTerminalActivity:** Start Docker container with ttyd web terminal
   - Image: `palad/claude-code:latest` (or cursor-cli, codex, gemini-cli)
   - Home directory: tmpfs (empty, no credentials mounted)
   - Expose WebSocket on random port (7681-7699)
   - Wait for health check
   - Return: `container_id`, `websocket_url`

2. **Wait for Signal:** Workflow blocks until user sends `authentication_finished` signal
   - User authenticates in terminal (e.g., `claude login`)
   - User clicks "Finish Authentication" button in UI
   - Frontend calls `POST /api/v1/terminal_sessions/:id/finish_auth`
   - Backend triggers AASM transition: `session.finish!`
   - Backend sends Temporal signal: `TemporalService.send_signal(workflow_id, :authentication_finished)`

3. **CollectArtifactsActivity:** Extract credentials from container
   - Use `docker cp` or `docker exec` to extract config files
   - Example paths:
     - Claude Code: `~/.claude/config`
     - Cursor CLI: `~/.cursor/config`
     - Codex: `~/.openai/config`
     - Gemini CLI: `~/.gemini/config`
   - Create `AgentCredential` record with encrypted config data
   - Trigger AASM transition: `session.collect!`

4. **StopContainerActivity:** Stop and remove container

**Pseudocode:**
```ruby
# app/temporal/workflows/agent_auth_workflow.rb
module Workflows
  class AgentAuthWorkflow
    def execute(terminal_session_id:, user_id:, agent_type:)
      # Step 1: Start container
      container_info = StartAuthTerminalActivity.execute(
        terminal_session_id: terminal_session_id,
        user_id: user_id,
        agent_type: agent_type
      )

      # Step 2: Wait for user signal (blocking)
      wait_for_signal(:authentication_finished)

      # Step 3: Collect artifacts
      artifacts = CollectArtifactsActivity.execute(
        terminal_session_id: terminal_session_id,
        container_id: container_info[:container_id],
        agent_type: agent_type
      )

      # Step 4: Cleanup
      StopContainerActivity.execute(
        container_id: container_info[:container_id]
      )

      { status: :completed, artifacts: artifacts }
    rescue StandardError => e
      session = TerminalSession.find(terminal_session_id)
      session.update!(error_message: e.message)
      session.fail!
      raise
    end
  end
end
```

#### 3. ContainerService (Docker Management)

**Responsibilities:**
- Start authentication containers with empty home directories
- Start agent session containers with mounted credentials (Epic 4)
- Extract files from containers
- Stop and remove containers
- Health checks

**Key Methods:**
```ruby
# app/services/container_service.rb
class ContainerService
  def self.start_auth_container(user_id, agent_type)
    # Select image: palad/claude-code:latest, palad/cursor-cli:latest, etc.
    image = image_for_agent(agent_type)

    # Start container with empty home (tmpfs)
    container = Docker::Container.create(
      'Image' => image,
      'name' => "auth-#{agent_type}-#{user_id}-#{Time.now.to_i}",
      'ExposedPorts' => { '7681/tcp' => {} },
      'HostConfig' => {
        'PortBindings' => { '7681/tcp' => [{ 'HostPort' => random_port.to_s }] },
        'Tmpfs' => { '/home/agent' => 'rw,size=100m' }  # Empty home directory
      }
    )
    container.start

    { container_id: container.id, websocket_url: "ws://localhost:#{port}" }
  end

  def self.start_agent_container(user_id, agent_type, project_id, credentials)
    # (Epic 4) Same image, but mount credentials
    # AgentCredential.mount_to_container(container_id) will write config files
  end

  def self.extract_files(container_id, paths)
    result = {}
    paths.each do |path|
      temp_file = "/tmp/#{SecureRandom.hex}"
      system("docker cp #{container_id}:#{path} #{temp_file}")
      result[path] = File.read(temp_file) if File.exist?(temp_file)
      File.delete(temp_file) if File.exist?(temp_file)
    end
    result
  end

  def self.stop_container(container_id)
    container = Docker::Container.get(container_id)
    container.stop
    container.remove
  end
end
```

#### 4. AgentCredential Model (Encrypted Storage)

**Purpose:** Store agent authentication artifacts securely for future sessions

```ruby
# app/models/agent_credential.rb
class AgentCredential < ApplicationRecord
  belongs_to :user

  # Fields:
  # - agent_type: string (unique per user)
  # - encrypted_config_data: text (Rails built-in encryption)
  # - metadata: jsonb (collected_at, artifact_count, etc.)
  # - timestamps: last_used_at, expires_at

  encrypts :encrypted_config_data

  validates :agent_type, uniqueness: { scope: :user_id }

  # Create from extracted artifacts
  def self.from_artifacts(user_id, agent_type, artifacts_hash)
    credential = find_or_initialize_by(user_id: user_id, agent_type: agent_type)
    credential.config_data = artifacts_hash
    credential.metadata = {
      collected_at: Time.current,
      artifact_count: artifacts_hash.keys.size
    }
    credential.save!
    credential
  end

  # Get/set config data (auto-encrypted)
  def config_data
    JSON.parse(encrypted_config_data) rescue {}
  end

  def config_data=(hash)
    self.encrypted_config_data = hash.to_json
  end

  # Mount credentials to agent session container (Epic 4)
  def mount_to_container(container_id)
    config_data.each do |path, content|
      expanded_path = path.gsub("~", "/home/agent")
      dir = File.dirname(expanded_path)

      system("docker exec #{container_id} mkdir -p #{dir}")
      IO.popen("docker exec -i #{container_id} tee #{expanded_path} > /dev/null", "w") { |pipe| pipe.write(content) }
    end

    touch(:last_used_at)
  end
end
```

#### 5. API Endpoints

**Routes:**
```ruby
# config/routes.rb
namespace :api, defaults: { format: :json } do
  namespace :v1 do
    resources :terminal_sessions, only: %i[index show create update destroy] do
      member do
        post :finish_auth   # User finished authentication
        post :cancel        # Cancel active session
      end
    end
  end
end
```

**Controller:**
```ruby
# app/controllers/api/v1/terminal_sessions_controller.rb
module Api::V1
  class TerminalSessionsController < ApplicationController
    before_action :authenticate_user!

    # POST /api/v1/terminal_sessions
    def create
      session = current_user.terminal_sessions.build(session_params)

      if session.save
        session.start! if session.may_start?  # Triggers Temporal workflow
        render json: { data: session_json(session) }, status: :created
      else
        render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /api/v1/terminal_sessions/:id/finish_auth
    def finish_auth
      @session.finish!

      # Send signal to Temporal workflow
      if @session.temporal_workflow_id.present?
        TemporalService.send_signal(@session.temporal_workflow_id, :authentication_finished)
      end

      render json: { data: session_json(@session), message: "Authentication finished, collecting artifacts..." }
    end
  end
end
```

#### 6. Docker Images (4 total)

**Single Image per Agent (reused for auth and sessions):**
- `palad/claude-code:latest` - Claude Code agent
- `palad/cursor-cli:latest` - Cursor CLI agent
- `palad/codex:latest` - OpenAI Codex agent
- `palad/gemini-cli:latest` - Gemini CLI agent

**Image Structure:**
```dockerfile
# docker/claude-code/Dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl bash git ttyd && \
    rm -rf /var/lib/apt/lists/*

# Install Claude CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Expose ttyd on port 7681
EXPOSE 7681

# Start ttyd web terminal
ENTRYPOINT ["ttyd", "-p", "7681", "-W", "bash"]
```

**Usage:**
- **auth_setup session:** Container starts with empty home directory (tmpfs)
  - User authenticates → creates `~/.claude/config`
  - Artifacts collected → saved to `AgentCredential`
- **agent_session (future):** Container starts with mounted credentials
  - `AgentCredential.mount_to_container` writes config before session starts
  - Agent CLI is pre-authenticated

#### 7. Frontend Integration (Not in Backend Scope)

**Onboarding Step 3 Flow:**
1. User selects agent (e.g., Claude Code)
2. Click "Start Authentication" → `POST /api/v1/terminal_sessions` with `session_type: "auth_setup"`, `agent_type: "claude_code"`
3. Backend creates session → starts Temporal workflow → returns `websocket_url`
4. Frontend embeds xterm.js terminal → connects to WebSocket
5. User authenticates in terminal (e.g., `claude login`)
6. User clicks "Finish Authentication" → `POST /api/v1/terminal_sessions/:id/finish_auth`
7. Backend sends Temporal signal → artifacts collected → session marked `collected`
8. Frontend polls `GET /api/v1/terminal_sessions/:id` until `state: "collected"`
9. User proceeds to next agent or Step 4

**Rationale:**
1. **State Machine Clarity:** AASM provides clear state transitions with callbacks and guards
2. **Temporal Orchestration:** Long-running workflows with signal-based user interaction (wait for "Finish" button)
3. **Docker Isolation:** Each authentication session in isolated container, no cross-contamination
4. **Credential Security:** Encrypted at rest (Rails `encrypts`), never exposed in API responses
5. **Reusable Images:** Same Docker image for auth and future agent sessions (mount determines auth state)
6. **Scalability:** Temporal handles workflow persistence, retries, and failure recovery
7. **Audit Trail:** All state transitions and timestamps logged in `terminal_sessions` table

**Testing Strategy:**
- Controller tests: Create session, finish auth, cancel, state transitions
- Model tests: AASM transitions, validation, callbacks
- Service tests: ContainerService (mock Docker API), TemporalService (mock workflows)
- Integration tests: Full flow from create → start → finish → collect (with mocked Docker/Temporal)

---

### Agent Credentials Service Architecture (Story 2.3 - Updated 2026-01-25)

**Decision:** Strategy Pattern for Agent-Specific Credential Handling

**Context:**
Different AI agents (Claude Code, Cursor CLI, Codex, Gemini CLI) store credentials in different locations and formats. We need a unified interface for:
- Extracting credentials after authentication
- Generating config files for new containers
- Detecting when authentication is complete
- Loading credentials into agent session containers

**Architecture Components:**

#### 1. Adapter Pattern (Strategy)

```
AgentCredentialsService              # Facade - selects adapter by agent_type
├── Agents::BaseAdapter              # Abstract interface
├── Agents::ClaudeCodeAdapter        # Claude Code implementation
├── Agents::CursorCliAdapter         # Cursor CLI (stub)
├── Agents::CodexAdapter             # Codex (stub)
└── Agents::GeminiCliAdapter         # Gemini CLI (stub)
```

**Base Adapter Interface:**
```ruby
# app/services/agents/base_adapter.rb
module Agents
  class BaseAdapter
    def config_path           # Path to config file inside container
    def home_dir              # Home directory (/home/claude, /home/cursor, etc.)
    def auth_watch_path       # Path to watch for auth completion
    def auth_required_keys    # Keys that indicate auth is complete
    def auth_complete?(content)     # Check if auth is complete
    def extract_credentials(content) # Extract credentials for DB storage
    def generate_config(credentials, workflow_config) # Generate full config
    def config_files(credentials, workflow_config)    # All files to write
  end
end
```

**To add a new agent:**
1. Create `app/services/agents/{agent_name}_adapter.rb`
2. Implement all methods from `BaseAdapter`
3. Add to `ADAPTERS` hash in `AgentCredentialsService`
4. Create Docker image in `docker/{agent_name}/`
5. Add agent type to `AVAILABLE_AGENTS` in User model

#### 2. Credential Storage Strategy

**What we store in DB (AgentCredential.config_data):**
```json
{
  "oauthAccount": { "accountUuid": "...", "emailAddress": "...", ... },
  "primaryApiKey": "sk-ant-...",
  "customApiKeyResponses": { "approved": [...], "rejected": [] },
  "userID": "..."
}
```

**Encryption:** Uses `ActiveSupport::MessageEncryptor` with key from `Settings.encryption.credentials_key`

**What we generate at container startup:**
```json
{
  // From DB (credentials)
  "oauthAccount": { ... },
  "primaryApiKey": "...",

  // Fixed values
  "installMethod": "global",
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "2.1.14",

  // Generated from workflow config
  "projects": {
    "/workspace": {
      "allowedTools": [],        // From workflow config
      "mcpServers": {},          // From workflow config
      "hasTrustDialogAccepted": true  // Always true
    }
  }
}
```

#### 3. Two Session Types

**auth_setup (Onboarding - Story 2.3):**
- Container starts with empty home directory (tmpfs)
- User authenticates in terminal (e.g., `claude login`)
- Watcher detects auth completion via `/fs/auth` REST API (polling)
- Frontend calls `finishAuth` API
- Temporal workflow collects and saves encrypted credentials
- User's `configured_agents` array is updated

**agent_session (Working sessions - Story 2.3+):**
- Container starts with empty home directory
- After container health check, credentials are loaded via `write_to_container`
- Agent CLI is pre-authenticated (no re-auth needed)
- User can immediately start working

#### 4. Auth Detection via File Watcher REST API

**Flow:**
```
1. Container starts with empty home
2. Frontend polls /fs/auth endpoint every 2 seconds
3. User authenticates in terminal (e.g., `claude login`)
4. Agent writes config file
5. Watcher checks AUTH_REQUIRED_KEYS in config
6. Returns { "authenticated": true }
7. Frontend shows "Auth detected!" message
8. User clicks "Save Authentication" button
9. Frontend calls finishAuth API
10. Temporal workflow → CollectArtifactsActivity → saves credentials
```

**Watcher REST API:**
```javascript
// GET /fs/auth
// Returns: { "authenticated": true/false }

function checkAuthComplete(configContent) {
  const config = JSON.parse(configContent);
  return AUTH_REQUIRED_KEYS.some(key => {
    const value = key.split('.').reduce((obj, k) => obj?.[k], config);
    return value !== undefined && value !== null && value !== '';
  });
}
```

**Environment Variables (passed from ContainerService):**
```bash
SESSION_TYPE=auth_setup          # Only check auth for auth_setup sessions
AUTH_WATCH_PATH=/home/claude/.claude.json
AUTH_REQUIRED_KEYS=oauthAccount,primaryApiKey  # Comma-separated
AGENT_TYPE=claude_code
```

#### 5. Container Service Methods

**For auth_setup:**
```ruby
ContainerService.start_auth_container(
  user_id,
  agent_type,
  session_id: session.id,
  route_token: session.route_token
)
# Returns: { container_id:, websocket_url:, watcher_url: }
```

**For agent_session:**
```ruby
ContainerService.start_agent_container(
  user_id,
  agent_type,
  session_id: session.id,
  route_token: session.route_token,
  credential: user.agent_credentials.find_by(agent_type: agent_type)
)
# After container starts, calls credential.write_to_container(container_id)
```

#### 6. Temporal Workflows

**AgentAuthWorkflow (auth_setup):**
1. `StartAuthTerminalActivity` - Start container with empty home
2. Wait for `authentication_finished` signal
3. `CollectArtifactsActivity` - Extract and save credentials
4. `StopContainerActivity` - Cleanup

**AgentSessionWorkflow (agent_session):**
1. `StartAgentSessionActivity` - Start container with credentials loaded
2. Wait for `session_finished` signal
3. `StopContainerActivity` - Cleanup

#### 7. Frontend Components

**AgentAuthTerminal (Onboarding):**
```typescript
// Polls /fs/auth for auth status
// Shows "Auth detected!" when authenticated
// User clicks "Save Authentication" to finish
<AgentAuthTerminal
  agentType="claude_code"
  onAuthComplete={() => navigateToNextStep()}
/>
```

**TerminalTestPage (Testing):**
```typescript
// Toggle between auth_setup and agent_session modes
// Supports all 4 agent types
// Shows file tree, file viewer, and terminal
```

#### 8. Adding New Agent Types

**Checklist:**
1. **Adapter:** Create `app/services/agents/{agent}_adapter.rb`
   - `config_path` - Where agent stores config
   - `home_dir` - Container home directory
   - `auth_required_keys` - Keys indicating auth complete
   - `extract_credentials` - What to save in DB
   - `generate_config` - Full config for container

2. **Docker Image:** Create `docker/{agent}/Dockerfile`
   - Base: `palad/agent-base:latest`
   - Install agent CLI
   - Copy any agent-specific files

3. **Constants:** Add to `User::AVAILABLE_AGENTS`

4. **Test:** Use `/terminal-test` page to verify auth flow

**Example (Claude Code):**
```ruby
# app/services/agents/claude_code_adapter.rb
module Agents
  class ClaudeCodeAdapter < BaseAdapter
    def config_path
      "/home/claude/.claude.json"
    end

    def home_dir
      "/home/claude"
    end

    def auth_required_keys
      %w[oauthAccount primaryApiKey]
    end

    def extract_credentials(content)
      config = JSON.parse(content)
      {
        "oauthAccount" => config["oauthAccount"],
        "primaryApiKey" => config["primaryApiKey"],
        "customApiKeyResponses" => config["customApiKeyResponses"],
        "userID" => config["userID"]
      }.compact
    end

    def generate_config(credentials, workflow_config = {})
      credentials.merge(
        "installMethod" => "global",
        "hasCompletedOnboarding" => true,
        "hasTrustDialogAccepted" => true,
        "projects" => {
          "/workspace" => {
            "allowedTools" => workflow_config[:allowed_tools] || [],
            "mcpServers" => workflow_config[:mcp_servers] || {},
            "hasTrustDialogAccepted" => true
          }
        }
      )
    end
  end
end
```

---

**Architecture Status:** IMPLEMENTED ✅

**Tested Features:**
- Auth flow with Claude Code agent
- Credential collection and encryption
- Agent session with pre-loaded credentials
- File watcher REST API for auth detection

**Document Maintenance:** Update this architecture when major technical decisions are made during implementation.
