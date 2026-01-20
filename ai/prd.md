---
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-03-success
  - step-04-journeys
  - step-05-domain
  - step-06-innovation
  - step-07-project-type
  - step-08-scoping
  - step-09-functional
  - step-10-nonfunctional
  - step-11-polish
inputDocuments:
  - ai/brainstorm-palad-platform.md
  - kb/product/vision.md
  - kb/product/architecture.md
  - ai/design-thinking-2026-01-15.md
  - ai/tech-design-xterm-docker-claude-code.md
  - kb/operations/team-coordination/tracking/weekly-plan.md
  - ai/project-overview.md
documentCounts:
  briefs: 0
  research: 0
  brainstorming: 1
  projectDocs: 6
workflowType: 'prd'
projectType: 'brownfield'
classification:
  projectType: 'saas_b2b'
  domain: 'developer_tools_ai_platform'
  complexity: 'medium'
  projectContext: 'brownfield'
  initialScope: 'internal_tool'
  billingModel: 'tbd'
  mvpFocus: 'full_platform'
---

# Product Requirements Document - Palad

**Author:** Artem
**Date:** 2026-01-20
**Version:** 1.0
**Status:** Draft

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Success Criteria](#success-criteria)
3. [Product Scope](#product-scope)
4. [User Journeys](#user-journeys)
5. [Domain-Specific Requirements](#domain-specific-requirements)
6. [Innovation & Novel Patterns](#innovation--novel-patterns)
7. [SaaS B2B Specific Requirements](#saas-b2b-specific-requirements)
8. [Project Scoping & Phased Development](#project-scoping--phased-development)
9. [Functional Requirements](#functional-requirements)
10. [Non-Functional Requirements](#non-functional-requirements)

---

## Executive Summary

### Product Vision

**Palad** — a cloud platform for orchestrating AI coding agents with a workflow system. The name comes from the myth of the Palladium — a sacred object that was the "anchor" of Troy's defense system.

### Problem Statement

Teams already use AI coding agents (Claude Code, Cursor, Codex) locally, but they run into problems:
- **No centralization** — everyone configures agents on their own
- **No sharing** — workflows, prompts, and settings are not reused
- **No transparency** — it is unclear how much the agents' work costs
- **No orchestration** — there are no step-by-step workflows with artifacts

### Solution

Palad solves these problems through:
- **Agent Orchestration** — a single platform for different agents in Docker
- **Workflow Engine** — BMAD-style step-by-step execution with artifacts
- **Billing & Analytics** — an MITM proxy for accurate token accounting
- **Shared Configuration** — centralized workflows, prompts, secrets

### Target Users

- **Primary:** A services company (~70 people), fixed-bid projects
- **Initial Scope:** An internal tool for the team
- **Future:** A public SaaS for external clients

### Key Differentiator

Palad is not yet another AI coding tool, but an **orchestration layer** for existing agents. We do not compete with Cursor or Claude Code — we make their use centralized and transparent.

### MVP Timeline

**8-12 weeks** with a team of 3 people (Artem, Andrey, Alexander)

---

## Success Criteria

### User Success

**"Aha!" moment:** When the agent + workflow together deliver a quality result — the agent found the right code, the workflow generated a ready PRD, and the exact cost is visible.

**Main criterion:** Artifact quality — an artifact (PRD, tech design, code) meets expectations with minimal iterations, and the user does not rewrite the artifact from scratch after the agent.

**Measurable criteria:**

| Metric | Target |
|---------|--------|
| Artifact accepted without substantial edits | ≥ 70% of cases |
| Number of iterations to "done" | ≤ 2 iterations |
| User comes back to use it again | Yes (retention) |

### Business Success

**Main goal:** Accelerating the development of fixed-bid projects in a services company (~70 people).

**Key metrics:**

| Metric | 3 months | 12 months |
|---------|----------|------------|
| Adoption | The team actively uses it | The standard tool for fixed-bid |
| Time saved | -20% time on the planning phase | -40% time on planning |
| Quality | Fewer reworks during the development stage | Predictable fixed-bid timelines |

**Business results:**
- Time savings on planning
- Artifact quality (PRD, tech design)
- Lower development cost
- Predictability of fixed-bid projects

### Technical Success

| Requirement | Criterion | Priority |
|------------|----------|-----------|
| Reliability | Sessions do not crash (< 1% failures) | High |
| Billing accuracy | Error < 5% of actual costs | High |
| Data safety | Artifacts are not lost (0% data loss) | High |
| Performance | Not critical for MVP | Low |

### Measurable Outcomes

**MVP Success (3 months):**
- [ ] The team uses Palad for the planning phase of fixed-bid projects
- [ ] Artifacts are generated with a quality of ≥ 70% acceptance rate
- [ ] Billing tracking works with an accuracy of ≥ 95%
- [ ] Zero data loss for artifacts

**Growth Success (12 months):**
- [ ] Palad — the standard tool for all fixed-bid projects
- [ ] Planning time has been reduced by 40%
- [ ] Readiness to open up to external users

---

## Product Scope

> **Note:** For the detailed roadmap and timeline — see the [Project Scoping & Phased Development](#project-scoping--phased-development) section

### Feature Overview

| Phase | Key Features |
|-------|--------------|
| **MVP** | Multi-agent sessions, Workflow Engine, MITM Billing, Artifacts, Basic UI |
| **Growth** | Human-in-the-loop, Webhooks, Tool marketplace, Analytics |
| **Vision** | Public SaaS, Subscription billing, Parallel steps, IDE integration |

---

## User Journeys

### Journey 1: Developer Misha — Interactive Implementation

**Persona:** Misha, 28 years old, middle developer

**Opening Scene:**
Misha received a task in Linear — "Implement user authentication API". The task contains a link to a tech design (an artifact from the planning phase). In the morning he opens Palad — it is his main work tool, and he rarely leaves the platform's perimeter.

**Rising Action:**
1. Misha sees his tasks from Linear in Palad
2. Selects a task → sees the related artifacts (tech design, PRD)
3. Selects **Interactive mode** — he wants to control every step
4. Starts a session with the agent (Claude Code / Codex)
5. The agent loads the context: codebase, tech design, related files

**Climax:**
Misha communicates with the agent in the terminal, clarifies details, approves changes. He sees how the agent finds the needed code and proposes solutions.

**Resolution:**
- The agent created a PR with the changes
- Misha sees a summary: what was done, which files were changed, the cost of the session
- The PR is ready for review

**Future Feature — PR Review in Cursor:**
> In the future: any PR can be opened in Cursor with the session context — files under review, change history. Solves the problem of reviewing large PRs.

---

### Journey 2: Tech Lead Katya — Planning Workflow

**Persona:** Katya, 35 years old, tech lead on fixed-bid projects

**Opening Scene:**
A new project — replatforming a legacy Java application. Katya opens Palad to start the planning phase.

**Rising Action:**
1. Katya creates a new Project in Palad
2. Loads assets: legacy codebase, documentation, call recordings
3. Selects a ready-made workflow: "Replatforming Planning"
4. Workflow steps:
   - Step 1: Code Analysis → artifact: "Legacy System Analysis"
   - Step 2: Requirements Discovery → artifact: "PRD"
   - Step 3: Architecture Design → artifact: "Tech Design"
   - Step 4: Task Breakdown → artifact: "Tasks" → export to Linear

**Climax:**
Katya selects Interactive mode — going through the steps as in BMAD. The agent asks questions, Katya answers. At each step: review the artifact → approve → next step.

**Resolution:**
- Planning phase complete
- Artifacts saved (PRD, Tech Design, Analysis)
- Tasks created in Linear with priorities
- Team ready for the Implementation phase

---

### Journey 3: Developer Sasha — Non-Interactive Batch

**Persona:** Sasha, 32 years old, senior developer, trusts agents

**Opening Scene:**
Sasha sees 5 tasks in the backlog. All have a tech design, all are clear. He doesn't want to spend time on interactive mode.

**Rising Action:**
1. Sasha selects tasks in Palad
2. For each one selects **Non-interactive mode**
3. Launches — the agents work
4. Goes to a meeting / other tasks

**Climax:**
The agents work autonomously. Each one creates a PR. Sasha receives notifications: "Task X completed, PR ready".

**Resolution:**
- Sasha comes back — sees the ready PRs
- For each one: summary, diff, cost
- Quick review, merge

---

### Journey 4: Admin Andrey — Platform Setup

**Persona:** Andrey, co-founder, configuring the platform

**Opening Scene:**
The team is growing, and Palad needs to be configured for new projects.

**Rising Action:**
1. Creates new Workflows: "Frontend Feature", "API Endpoint", "Bug Fix"
2. Configures Secrets: Platform level (API keys), Project level (GitHub tokens)
3. Creates custom Tools: "Transcribe Meeting", "Read Slack Channel"

**Resolution:**
- Platform configured
- Workflows ready to use
- Tools available in all sessions

---

### Journey 5: PM Lena — Tracking & Costs

**Persona:** Lena, 30 years old, project manager on a fixed-bid

**Opening Scene:**
A fixed-bid project is in full swing. Need to understand the AI spend.

**Rising Action:**
1. Opens the Dashboard in Palad
2. Sees: Total cost, breakdown by workflows/users, sessions history

**Resolution:**
- Sees that we're staying within budget
- Can show the client a transparency report

---

### Journey Requirements Summary

| Journey | Revealed Capabilities |
|---------|----------------------|
| Developer Interactive | Session management, Agent selection, Mode toggle, Artifact viewer |
| Developer Non-Interactive | Async execution, Notifications, PR integration |
| Tech Lead Planning | Workflow selection, Asset upload, Step-by-step execution, Linear export |
| Admin Setup | Workflow builder, Secrets management, Tool creation |
| PM Tracking | Dashboard, Cost analytics, Usage reports |

### Two Global Phases

**Planning Phase:**
- Workflows: Brainstorm → PRD → Architecture → Task Breakdown
- Output: Artifacts + Tasks in Linear
- Mode: Interactive (recommended) / Non-interactive

**Implementation Phase:**
- SDLC: Tech Design → Implementation → QA
- Output: PRs, Code changes
- Mode: Interactive / Non-interactive (user choice)

---

## Domain-Specific Requirements

### Compliance & Regulatory

| Requirement | Priority | Notes |
|-------------|----------|-------|
| **SOC 2 Type II** | High (for public SaaS) | Required when opening to external customers |
| **GDPR basics** | Medium | User data handling, right to deletion |

**SOC 2 Trust Service Criteria:**
- Security — access controls, encryption, monitoring
- Availability — uptime, disaster recovery
- Confidentiality — data protection, secrets management
- Processing Integrity — accurate data processing
- Privacy — personal data handling

### Technical Constraints

| Constraint | Requirement |
|------------|-------------|
| **Secrets Security** | Encrypted at rest, secrets hierarchy (Platform → Company → Workflow) |
| **Multi-tenancy Isolation** | Data isolation between companies, container isolation between sessions |
| **Audit Logging** | All actions logged for SOC 2 compliance |
| **Encryption** | TLS in transit, encryption at rest for sensitive data |

### Integration Requirements

| Integration | Purpose |
|-------------|---------|
| **LLM Providers** | Anthropic, OpenAI, OpenRouter — provider agnostic |
| **Linear** | Task export from planning workflows |
| **GitHub/GitLab** | PR creation, code context |
| **S3** | Artifact storage |

### Risk Mitigations

| Risk | Mitigation |
|------|------------|
| **Runaway API costs** | Budget alerts, rate limiting, cost tracking per session |
| **Data leakage between tenants** | Strict isolation, separate containers, access controls |
| **LLM provider outage** | Fallback to alternative providers |
| **Secrets exposure** | Encrypted storage, audit logs, rotation policies |

---

## Innovation & Novel Patterns

### Detected Innovation Areas

**Core Innovation:** Centralization and orchestration of AI agents — not the agents themselves (they already exist locally), but everything around them:

| Innovation | Description |
|------------|-------------|
| **Global Workflows** | Sharing workflows across the team, versioning, reuse |
| **Agent Orchestration** | A single platform for different agents (Claude Code, Codex, OpenCode, Cursor CLI) |
| **Shared Prompts & Settings** | Centralized storage of prompts, settings, secrets |
| **Billing & Analytics** | Transparency of costs across all agents and workflows |
| **MITM Billing Approach** | An innovative approach to tracking without modifying the agents |

### Assumptions Being Challenged

| Assumption | Challenge |
|------------|-----------|
| "Coding agents must be local" | A cloud platform with the same agents |
| "Can't share workflows across the team" | Centralized storage and reuse |
| "Everyone configures agents themselves" | Shared settings, prompts, tools at the company level |
| "Can't accurately track CLI agent costs" | MITM Proxy solves this problem |

### Market Context & Competitive Landscape

| Competitor | What They Do | Palad Differentiation |
|------------|--------------|----------------------|
| **Cursor** | Local IDE with AI | Palad = cloud orchestration layer |
| **Replit Agents** | Cloud coding | Palad = agent-agnostic, workflow-focused |
| **GitHub Copilot Workspace** | Cloud AI coding | Palad = BMAD-style workflows, multi-agent |
| **n8n / Zapier** | Workflow automation | Palad = AI agents as workflow steps |

**Unique Position:** Palad is not just another AI coding tool, but an **orchestration layer** for existing agents with workflows, sharing, and billing.

### Validation Approach

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Daily Active Usage** | Team uses it as the primary tool | DAU/WAU ratio > 0.6 |
| **Fixed-bid Success** | Projects stay within budget | % of projects on-budget |
| **Workflow Adoption** | Workflows are reused | # workflow runs / # unique workflows |
| **Agent Coverage** | MITM works with all 4 agents | 4/4 agents supported |

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **MITM doesn't work with agent X** | Fallback: log parsing, wrapper scripts, provider API usage reports |
| **Agents update breaks integration** | Version pinning, integration tests, quick response team |
| **Users prefer local tools** | Seamless experience, clear value (sharing, billing), Cursor integration via MCP |

---

## SaaS B2B Specific Requirements

### Project-Type Overview

Palad is a B2B SaaS platform for orchestrating AI agents with a workflow system. The focus is on simplicity and minimal overhead for internal use, with the ability to scale to external clients.

### Multi-Tenancy Model

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

### Permission Model (RBAC)

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

### Subscription Tiers

**TBD** — to be defined later. The MVP works without a billing model.

### Integration Architecture

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

### Implementation Considerations

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

## Project Scoping & Phased Development

### MVP Strategy & Philosophy

**MVP Approach:** Experience + Platform MVP
- Full UX for core workflows
- Extensible tools framework
- Internal tool first (one company)

**Team:** 3 people
- Artem — BMAD method, UI, workflows
- Andrey — AI part, agents, integrations
- Alexander — Full-stack development

### MVP Feature Set (Phase 1)

**Core User Journeys Supported:**
- ✅ Developer Interactive — coding sessions with the agent
- ✅ Developer Non-Interactive — async execution
- ✅ Tech Lead Planning — workflow execution with artifacts
- ⏳ Admin Setup — basic (workflows, secrets)
- ⏳ PM Tracking — basic (session costs)

**Must-Have Capabilities:**

| Feature | Priority | Notes |
|---------|----------|-------|
| Multi-agent sessions | P0 | Claude Code + 1-2 other agents |
| Interactive mode | P0 | Terminal + file viewer |
| Non-interactive mode | P0 | Async execution |
| Workflow Engine | P0 | Steps, artifacts, BMAD-style |
| MITM Billing | P0 | Token tracking, cost per session |
| Artifacts to S3 | P0 | Upload, download, transfer between steps |
| Basic Workflow UI | P0 | CRUD workflows, run, view results |
| Session management | P0 | Start, stop, view history |
| Secrets management | P1 | Platform + workflow level |
| Basic Tools framework | P1 | At least 1-2 custom tools |

### Post-MVP Features (Phase 2)

| Feature | Trigger for Development |
|---------|------------------------|
| Human-in-the-loop | After core workflows stable |
| Webhook triggers | User demand for automation |
| More agents | After MITM validated with first 2 |
| Analytics dashboard | After 1 month of usage data |
| Tool marketplace | After tools framework proven |
| Linear integration | After manual task export validated |

### Vision Features (Phase 3)

| Feature | Prerequisite |
|---------|--------------|
| Public SaaS | Internal validation complete |
| Multi-tenancy (companies) | Public launch decision |
| Subscription billing | Revenue model defined |
| Parallel steps | Advanced use cases emerge |
| Cursor/MCP integration | After platform stable |
| PR Review in Cursor | After core PR flow works |

### Risk Mitigation Strategy

**Technical Risks:**

| Risk | Probability | Mitigation |
|------|-------------|------------|
| MITM doesn't work with agent X | Medium | Test each agent early; fallback to log parsing |
| Agent updates break integration | Medium | Version pinning, integration tests |
| Workflow engine complexity | Low | Start simple, iterate |

**Validation Plan for MITM:**
1. Week 1: Test MITM with Claude Code
2. Week 2: Test MITM with Codex
3. Week 3: Test MITM with OpenCode
4. Week 4: Test MITM with Cursor CLI
5. For each failure: develop fallback (log parsing, wrapper)

**Market Risks:**

| Risk | Mitigation |
|------|------------|
| Team doesn't adopt | Dogfood heavily, iterate on UX |
| Workflows too complex | Start with simple templates |
| Cost tracking not valuable | Talk to users early |

**Resource Risks:**

| Risk | Mitigation |
|------|------------|
| 3 people not enough | Focus ruthlessly on MVP |
| Someone leaves | Document everything, pair programming |
| Scope creep | Strict MVP boundaries |

### Timeline Estimate

**MVP Target:** ~8-12 weeks with 3 people

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Foundation | Weeks 1-4 | MITM validation, workflow engine core, agent sessions |
| Integration | Weeks 5-8 | Full workflow execution, artifacts, billing |
| Polish | Weeks 9-12 | UI, testing, dogfooding, iteration |

---

## Functional Requirements

### Agent Sessions

- **FR1:** User can start a new agent session with selected agent type (Claude Code, Codex, OpenCode, Cursor CLI)
- **FR2:** User can choose between Interactive and Non-interactive mode when starting a session
- **FR3:** User can interact with agent through web terminal in Interactive mode
- **FR4:** User can view file tree of session workspace in real-time
- **FR5:** User can view and browse files in session workspace (code, images, PDF)
- **FR6:** User can stop an active session
- **FR7:** User can view session history with status and outcomes
- **FR8:** System automatically tracks token usage during session via MITM proxy
- **FR9:** User can see session cost (tokens, USD) after session completes

### Workflow Management

- **FR10:** Admin can create new workflow with name, description, and steps
- **FR11:** Admin can define workflow steps with agent type, prompt template, and expected artifacts
- **FR12:** Admin can edit existing workflows
- **FR13:** Admin can delete workflows
- **FR14:** User can view list of available workflows
- **FR15:** User can start workflow execution with selected input assets
- **FR16:** User can execute workflow steps in Interactive mode (step-by-step with approval)
- **FR17:** User can execute workflow in Non-interactive mode (automated)
- **FR18:** System passes artifacts between workflow steps automatically

### Artifact Management

- **FR19:** User can upload assets (files, archives) to project
- **FR20:** User can view list of artifacts in project
- **FR21:** User can download artifacts
- **FR22:** User can delete artifacts
- **FR23:** System stores artifacts in S3 with metadata in database
- **FR24:** System preserves artifact history and versioning
- **FR25:** Workflow steps can reference artifacts from previous steps as input

### Project & Collaboration

- **FR26:** Admin can create new project within company
- **FR27:** Admin can add collaborators to project
- **FR28:** Admin can remove collaborators from project
- **FR29:** Collaborator can access all project resources (sessions, workflows, artifacts)
- **FR30:** User can view list of projects they have access to
- **FR31:** User can switch between projects

### Secrets Management

- **FR32:** Admin can create secrets at platform level
- **FR33:** Admin can create secrets at workflow level
- **FR34:** System injects appropriate secrets into agent sessions
- **FR35:** Secrets are encrypted at rest
- **FR36:** User cannot view secret values after creation (write-only)

### Tools Framework

- **FR37:** Admin can create custom tool with Docker image and configuration
- **FR38:** Admin can specify required secrets for tool
- **FR39:** Agent can invoke tools during session via MCP
- **FR40:** System executes tool as Temporal Activity (sync)
- **FR41:** Tool results are returned to agent

### Billing & Analytics

- **FR42:** User can view total cost for project
- **FR43:** User can view cost breakdown by workflow
- **FR44:** User can view cost breakdown by user
- **FR45:** User can view session history with costs
- **FR46:** Admin can view company-wide usage statistics

### User Management

- **FR47:** User can sign in via Google OAuth
- **FR48:** Admin can invite users to company
- **FR49:** Admin can assign user roles (Admin, Collaborator)
- **FR50:** Admin can remove users from company

### Integrations

- **FR51:** System can export tasks to Linear from workflow output
- **FR52:** System can load code context from GitHub repository
- **FR53:** System can create PR in GitHub from session output

---

## Non-Functional Requirements

### Security

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-S1** | All API keys and secrets encrypted at rest (AES-256) | Protect sensitive credentials |
| **NFR-S2** | All data in transit encrypted via TLS 1.2+ | Standard security practice |
| **NFR-S3** | Session data isolated by company_id — no cross-tenant access | Multi-tenancy isolation |
| **NFR-S4** | Audit log for all admin actions (user management, secrets, workflows) | SOC 2 preparation |
| **NFR-S5** | Secrets never logged or displayed after creation | Prevent credential exposure |
| **NFR-S6** | Docker containers isolated per session | Prevent cross-session data leakage |

### Reliability

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-R1** | Session failure rate < 1% | Core success metric |
| **NFR-R2** | Zero data loss for artifacts (stored in S3 with redundancy) | Business critical |
| **NFR-R3** | Billing accuracy ≥ 95% of actual token usage | Key differentiator |
| **NFR-R4** | Graceful degradation when LLM provider unavailable | Fallback to alternative |
| **NFR-R5** | Session state preserved on unexpected termination | User doesn't lose work |

### Integration

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-I1** | Support multiple LLM providers (Anthropic, OpenAI, OpenRouter) | Provider agnostic |
| **NFR-I2** | MITM proxy compatible with all 4 target agents | Core billing feature |
| **NFR-I3** | GitHub API integration for repo access and PR creation | Core workflow feature |
| **NFR-I4** | Linear API integration for task export | Planning workflow output |
| **NFR-I5** | Temporal orchestration for all workflow execution | Reliability, retry, visibility |

### Operability

| ID | Requirement | Rationale |
|----|-------------|-----------|
| **NFR-O1** | Structured logging for all services | Debugging, monitoring |
| **NFR-O2** | Health checks for all containers | Kubernetes readiness |
| **NFR-O3** | Temporal UI accessible for workflow debugging | Developer experience |
