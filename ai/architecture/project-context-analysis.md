# Project Context Analysis

## Requirements Overview

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

## Scale & Complexity

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

## Technical Constraints & Dependencies

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

## Cross-Cutting Concerns Identified

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
