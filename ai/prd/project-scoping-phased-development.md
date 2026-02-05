# Project Scoping & Phased Development

## MVP Strategy & Philosophy

**MVP Approach:** Experience + Platform MVP
- Full UX for core workflows
- Extensible tools framework
- Internal tool first (one company)

**Team:** 3 people
- Artem — BMAD method, UI, workflows
- Andrey — AI part, agents, integrations
- Alexander — Full-stack development

## MVP Feature Set (Phase 1)

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

## Post-MVP Features (Phase 2)

| Feature | Trigger for Development |
|---------|------------------------|
| Human-in-the-loop | After core workflows stable |
| Webhook triggers | User demand for automation |
| More agents | After MITM validated with first 2 |
| Analytics dashboard | After 1 month of usage data |
| Tool marketplace | After tools framework proven |
| Linear integration | After manual task export validated |

## Vision Features (Phase 3)

| Feature | Prerequisite |
|---------|--------------|
| Public SaaS | Internal validation complete |
| Multi-tenancy (companies) | Public launch decision |
| Subscription billing | Revenue model defined |
| Parallel steps | Advanced use cases emerge |
| Cursor/MCP integration | After platform stable |
| PR Review in Cursor | After core PR flow works |

## Risk Mitigation Strategy

**Technical Risks:**

| Risk | Probability | Mitigation |
|------|-------------|------------|
| MITM doesn't work with agent X | Medium | Test each agent early; fallback to log parsing |
| Agent updates break integration | Medium | Version pinning, integration tests |
| Workflow engine complexity | Low | Start simple, iterate |

**Validation Plan for MITM:**
1. Week 1: Test MITM with Claude Code
2. Week 2: Test MITM with Codex
3. Week 3: Test MITM with Gemini CLI
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

## Timeline Estimate

**MVP Target:** ~8-12 weeks with 3 people

> **Note:** See [Workflow Architecture](./workflow-architecture.md) for detailed dependency graph and implementation phases.

### Implementation Phases (Updated)

| Phase | Scope | Deliverable |
|-------|-------|-------------|
| **Phase 0** | Secrets Management | Encrypted secrets CRUD, injection into containers |
| **Phase 1** | Agents | Agent model, CRUD, selection in sessions |
| **Phase 2** | Tools | Tool definitions, Docker execution, Temporal activities |
| **Phase 3** | MCP Servers | MCP config, tool exposure, connection to CLI agents |
| **Phase 4** | Session Context | Per-CLI configuration, credentials injection, MCP wiring |
| **Phase 5** | Workflows Core | Workflow/Step CRUD, WorkflowRun/StepRun |
| **Phase 6** | Artifacts | Collection, versioning, S3, validation |
| **Phase 7** | Advanced | Builder, non-interactive, GitHub integration |

### Dependency Graph

```
WORKFLOWS (Phase 5-6)
    ↓ depends on
SESSION CONTEXT (Phase 4)
    ↓ depends on
MCP SERVERS (Phase 3)
    ↓ depends on
TOOLS (Phase 2)
    ↓ depends on
AGENTS (Phase 1)
    ↓ depends on
SECRETS MANAGEMENT (Phase 0)
```

---
