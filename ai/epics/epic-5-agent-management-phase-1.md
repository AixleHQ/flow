# Epic 5: Agent Management (Phase 1)

Admins can create and manage agent configurations with personas.
**Agents are independent of workflows** — they can be used in standalone sessions or workflow steps.

**FRs covered:** FR37, FR38, FR39, FR40, FR41, FR42

**Phase:** 1 (Depends on: Epic 4 Secrets)

**User Outcome:** Reusable agent configurations with personas for standalone sessions and workflows.

## Story 5.1: Agent CRUD with Scoping

As a company admin,
I want to create and manage agent configurations with persona details,
So that agents can be reused across standalone sessions and workflows.

**Acceptance Criteria:**
- Can create agent with: name, title, icon (emoji), persona, communication_style, principles
- Agent scoped to company or project level (polymorphic scope)
- Can edit and delete agents
- Project agents override company agents with same name (merged list)
- Source tracking: `custom` or `bmad_import`
- UI for managing agents (company-level and project-level)

## Story 5.2: Import Agents from BMAD Files

As a company admin,
I want to import agent configurations from BMAD files,
So that I can reuse existing agent definitions.

**Acceptance Criteria:**
- Can upload BMAD agent files (.md)
- Parser extracts persona, communication_style, principles
- Creates Agent record with imported data (source: bmad_import)
- Shows preview before import

## Story 5.3: Select Agent for Session

As a user,
I want to select an agent when starting a standalone session,
So that the agent's persona is applied to my interaction.

**Acceptance Criteria:**
- Session start shows available agents (merged company + project)
- Can select agent for the session
- Selected agent's persona injected as system prompt
- Agent selection saved with session record

---
