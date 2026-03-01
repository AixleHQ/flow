---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
inputDocuments:
  - ai/session-context-constructor.md
  - ai/prd/functional-requirements.md
  - ai/prd/non-functional-requirements.md
  - ai/architecture/index.md
  - ai/architecture/core-architectural-decisions.md
  - ai/architecture/workflow-system.md
  - ai/epics/epic-8-session-context-phase-4.md
  - app/services/session_context_service.rb
---

# app - Epic Breakdown (Session Context Constructor)

## Overview

This document provides the complete epic and story breakdown for the Session Context Constructor feature, decomposing the requirements from the design document (`ai/session-context-constructor.md`), PRD, and Architecture into implementable stories. This builds on top of the existing Epic 8 (Session Context Phase 4) which covered basic per-CLI configuration injection (FR53-FR56).

Stories are maintained in sharded epic files under `ai/epics/`.

## Requirements Inventory

### Functional Requirements

**Existing PRD Requirements (related scope):**

FR53: Admin can configure session context per CLI type (Claude Code, Cursor CLI, Codex, Gemini CLI)
FR54: System injects config files into container based on CLI type
FR55: System injects environment variables with resolved secrets
FR56: System connects configured MCP servers to session

**New Requirements (from session-context-constructor.md):**

FR-SCC1: System assembles session context through a unified pipeline (SessionContextConstructor) for all session types (standalone, workflow step, board-triggered)
FR-SCC2: System structures context content using XML-tagged sections with priority levels (critical/important/info)
FR-SCC3: System composes context from independent builders (CriticalRules, AgentRole, SessionInfo, Workspace, WorkflowContext, BoardContext, Tools, Resources, OutputRules)
FR-SCC4: System injects workflow context (workflow overview, current step, sub-steps checklist, previous steps summary) into agent session context file
FR-SCC5: System injects board task context (board name, task details, column, recent comments) into agent session context file when session is board-triggered
FR-SCC6: System applies builder applicability rules — each builder runs only for relevant session types per the Session Type Matrix
FR-SCC7: System separates context file (who you are + rules) from AGENT_PROMPT env var (what to do)
FR-SCC8: System applies sandwich pattern — critical rules placed both at beginning and end of context
FR-SCC9: System compresses sections when context exceeds token budget (~6000 tokens threshold)
FR-SCC10: System produces structured JSON metadata (builders applied/skipped, section sizes, token estimates, session type) for traceability and debugging

### NonFunctional Requirements

**Existing PRD Requirements (related scope):**

NFR-S6: Docker containers isolated per session — context must not leak between sessions
NFR-R5: Session state preserved on unexpected termination

**New Requirements (from design document):**

NFR-SCC1: Each context builder must be independently testable in isolation
NFR-SCC2: XML tags must have matching open/close pairs (machine-validatable)
NFR-SCC3: XML overhead must not exceed ~5% of context size (~100-200 tokens on avg 2000-4000 token context)
NFR-SCC4: Context rendering order must be deterministic and consistent across builds
NFR-SCC5: Migration must be incremental (6-phase) — no big-bang replacement of existing SessionContextService

### Additional Requirements

- AR1: Current `SessionContextService#build_context_content` produces plain markdown — must be replaced with XML-structured output via ContextRenderer
- AR2: `WorkflowContextAssembler` is orphaned code — must be deleted during cleanup phase
- AR3: `WorkflowStepStrategy#build_workflow_prompt` duplicates context assembly — must be simplified to only pass step instructions via AGENT_PROMPT
- AR4: `BoardContextResolver` is currently only used inside board MCP tools — board context must be injected proactively into session context via BoardContextBuilder
- AR5: Migration follows 6 phases: (1) create Constructor + builders with markdown output, (2) switch SessionContextService to use Constructor, (3) add XML tags to renderer, (4) move workflow context from WorkflowStepStrategy to WorkflowContextBuilder, (5) add BoardContextBuilder, (6) delete WorkflowContextAssembler + cleanup
- AR6: Constructor must integrate with `AgentSessionStrategy#before_exec` hook via `SessionContextService.assemble_session_context`
- AR7: Context file paths are adapter-specific (CLAUDE.md, AGENTS.md, GEMINI.md) — Constructor output must work with all agent adapters

### FR Coverage Map

| Requirement | Epic | Description |
|-------------|------|-------------|
| FR-SCC1 | Epic 25 (Story 25.5) | Unified pipeline for all session types |
| FR-SCC2 | Epic 25 (Story 25.1) | XML-tagged sections with priority levels |
| FR-SCC3 | Epic 25 (Stories 25.2-25.4) | Independent composable builders |
| FR-SCC4 | Epic 26 (Stories 26.1-26.4) | Workflow context injection |
| FR-SCC5 | Epic 27 (Stories 27.1-27.2) | Board task context injection |
| FR-SCC6 | Epic 25 (Story 25.5) | Builder applicability rules per session type |
| FR-SCC7 | Epic 26 (Story 26.5) | Context file vs AGENT_PROMPT separation |
| FR-SCC8 | Epic 25 (Stories 25.2, 25.4) | Sandwich pattern for critical rules |
| FR-SCC9 | Epic 28 (Story 28.1) | Token budget compression |
| FR-SCC10 | Epic 25 (Stories 25.5-25.6) | JSON traceability metadata |

## Epic List

### [Epic 25: Unified Context Constructor & XML Renderer](./epics/epic-25-unified-context-constructor.md)
7 stories — composable pipeline, XML renderer, core builders, orchestrator, ContextResult, traceability, integration
**FRs covered:** FR-SCC1, FR-SCC2, FR-SCC3, FR-SCC6, FR-SCC8, FR-SCC10

### [Epic 26: Workflow Context in Agent Sessions](./epics/epic-26-workflow-context-in-sessions.md)
5 stories — workflow builder, sub-steps, previous steps, workflow tools, AGENT_PROMPT cleanup
**FRs covered:** FR-SCC4, FR-SCC7

### [Epic 27: Board Task Context in Agent Sessions](./epics/epic-27-board-context-in-sessions.md)
2 stories — board context builder, recent comments
**FRs covered:** FR-SCC5

### [Epic 28: Context Optimization & Legacy Cleanup](./epics/epic-28-context-optimization-cleanup.md)
3 stories — token compression, delete orphaned code, strategy cleanup
**FRs covered:** FR-SCC9

## Session Config Cascade (Epics 29-31)

**New Requirements (from session-config-cascade.md):**

FR-CC1: System resolves session configuration (agent_runtime, tools, skills, mcp_servers, repositories, assets) through a single SessionConfigResolver with session-centric API
FR-CC2: Resources (tools, skills, MCP servers, assets) are merged additively — each level supplements, never overrides
FR-CC3: Workflow can define base resources (tools, skills, MCP, assets) available in all steps
FR-CC4: User has a default agent credential (auto-set to last created) used as baseline runtime
FR-CC5: Board task assets are automatically injected as input assets in board-triggered sessions
FR-CC6: Step can require a specific agent_runtime that overrides user default
FR-CC7: Standalone session launch prefills agent_runtime from user's default credential
FR-CC8: Workflow Builder UI supports base resources configuration and "Inherit All" toggle
FR-CC9: Workflow Builder shows "Effective" resource hints per step (base + step union)

### [Epic 29: Session Config Resolver](./epics/epic-29-session-config-resolver.md)
7 stories — SessionConfigResolver core, additive resolution, inherit_all, board task assets, step required_agent_runtime, integration, traceability
**FRs covered:** FR-CC1, FR-CC2, FR-CC3, FR-CC5, FR-CC6

### [Epic 30: Default Agent Credential & Profile UI](./epics/epic-30-default-agent-credential.md)
3 stories — User default_agent_credential_id, Profile UI selector, standalone session prefill
**FRs covered:** FR-CC4, FR-CC7

### [Epic 31: Workflow Base Resources & Builder UI](./epics/epic-31-workflow-base-resources-ui.md)
4 stories — Base resources API, Builder UI section, Inherit All toggle, step required_agent_runtime selector
**FRs covered:** FR-CC8, FR-CC9
