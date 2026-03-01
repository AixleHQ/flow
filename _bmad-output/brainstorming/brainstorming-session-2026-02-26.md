---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: []
session_topic: 'AI-powered Board/Tasks system with automatic workflow triggers and MCP tools for agents'
session_goals: 'Design architecture for Board with configurable columns/presets, automatic workflow triggers on column transitions, internal MCP tools for agent-driven task management, feedback loop between humans and AI agents via tagged comments'
selected_approach: 'ai-recommended'
techniques_used: ['Morphological Analysis', 'Cross-Pollination', 'Chaos Engineering']
ideas_generated: 42
context_file: ''
session_active: false
workflow_completed: true
facilitation_notes: 'User demonstrates strong pragmatic engineering sense — consistently choosing simplicity over overengineering, deferring complexity until needed. Clear YAGNI mindset. Strong product intuition around AI-agent interaction patterns.'
---

# Brainstorming Session Results

**Facilitator:** Artem_petrov
**Date:** 2026-02-26

## Session Overview

**Topic:** AI-powered Board/Tasks system with automatic workflow triggers and MCP tools for agents
**Goals:** Design architecture for Board with configurable columns/presets, automatic workflow triggers on column transitions, internal MCP tools for agent-driven task management, feedback loop between humans and AI agents via tagged comments

### Context

System already has working workflows. Goal is to implement all BMAD workflows as internal workflows, creating a semi-automatic development system. BMAD workflows can be converted to internal workflows via a dedicated system workflow ("Framework Importer"). The system is called PALAD.

### Session Setup

User wants to build a task management board inside projects with:
- Configurable column presets (simple Kanban to full SDLC)
- Custom column management (add/remove/reorder)
- Automatic workflow triggers on column entry
- Internal MCP tools for agents to interact with tasks
- Tagged comments for human-AI feedback loop

## Technique Selection

**Approach:** AI-Recommended Techniques

- **Morphological Analysis** (deep): Systematically decompose all system components into parameters and explore combinations
- **Cross-Pollination** (creative): Transfer proven patterns from Jira, Linear, GitHub Projects, n8n, Temporal into AI-native design
- **Chaos Engineering** (wild): Stress-test architecture by deliberately exploring failure modes and edge cases

---

## Technique Execution Results

### Morphological Analysis — 7 Parameters

#### Parameter 1: Column Model

**Decision: Simple column + optional workflow + purpose field**

Column is a lightweight entity: name, position, optional workflow binding, and a `purpose` text field that describes the column's role for AI agents (e.g. "Technical design is being created. Expected output: comment with tag tech_design").

Alternatives considered and rejected:
- Column with on_enter/on_exit rules — overengineering for current needs
- Column with role model (human/agent/both) — not needed, workflow itself determines this

#### Parameter 2: Board Presets

**Decision: Preset as starting point → free customization**

User selects a preset (Simple Kanban, Dev Team, Full SDLC, etc.) and gets a set of columns. After that, they can add/remove/rename/reorder columns freely. Preset "detaches" after first modification — the board lives independently.

Alternatives considered and rejected:
- Hard presets without customization — too rigid
- Library of columns as constructor — too high entry barrier
- Presets with pre-configured workflows — good idea but deferred, start with column-only presets

#### Parameter 3: Task Model

**Decision: Structured task with types and assets**

- **Base fields:** title, description, assignee, tags, column_id, priority
- **task_type:** `epic`, `story`, `bug`, `not_specified`
- **Epic → Story:** has_many relationship
- **Comments:** separate entity with tags and author_type
- **Assets:** files attached directly to the task (not to workflow/project/company). Agent attaches via internal MCP tool.

#### Parameter 4: Comment System

**Decision: Flat comments with tags and author_type**

- Flat, chronological list (no threading)
- Tags on comments: `tech_design`, `code_review`, `qa_report`, `feedback`, etc.
- `author_type`: human / agent / system
- Agent reads context via `get_comments(task_id, tag: "tech_design")` — gets both its previous output and user feedback
- Filtering by tag replaces the need for threaded discussions

#### Parameter 5: Workflow Triggers

**Decision: auto/manual mode + cooldown**

- Two trigger modes configurable per column-workflow binding: `auto` (fires immediately on task entry) or `manual` (user clicks to start)
- Cooldown to prevent accidental double-triggers from drag-and-drop jitter
- No blocking of repeated runs — re-running workflow on task return is valid behavior (feedback loop scenario)
- Workflow binding only from project-scoped workflows (copy to project first if needed)
- Cannot delete a workflow that is bound to a column (validation on delete)

#### Parameter 6: Internal MCP Tools (13 tools)

**Read tools:**
1. `list_tasks(column_name?, tag?, task_type?, assignee?)` — list tasks with filtering
2. `get_task(task_id)` — full task info
3. `get_comments(task_id, tag?, author_type?)` — comments with filtering
4. `get_task_assets(task_id, tag?)` — task assets
5. `get_board_info()` — board structure (columns, purposes, workflow bindings)

**Write tools:**
6. `create_task(title, description, task_type, column_name?, tags?)` — create task
7. `update_task(task_id, ...)` — update task fields
8. `move_task(task_id, column_name)` — move task to column
9. `add_comment(task_id, body, tags?)` — add comment (author_type: agent auto)
10. `attach_asset(task_id, file, name?, tags?)` — attach file to task
11. `add_tag(entity_type, entity_id, tag)` / `remove_tag(...)` — tag management

**Self-diagnostic tools:**
12. `fail_session(reason)` — agent terminates session with error if stuck/looping
13. `request_human_help(question)` — agent pauses session and asks for human input

**Note:** `board_id` is never passed — determined automatically from session/workflow run context. One board per project.

#### Parameter 7: BMAD → PALAD Converter (System Workflow)

**Decision: System workflow "Framework Importer" with wow-effect visualization**

- Separate system workflow type with special capabilities
- Input: external framework repository/documentation (e.g. BMAD `llms-full.txt`) + PALAD documentation (available tools, agents, skills, workflows)
- Agent-converter persona that understands both worlds and maps one to another
- Workflow steps generate: agents, MCP tools, skills, workflow steps
- Real-time visualization: alongside the session, user sees a tree of artifacts being created (agent created → tool created → skill created → workflow step created)
- This is the "wow effect" — watching the system self-assemble

---

### Cross-Pollination — Patterns from Other Systems

#### From Linear / Jira / GitHub Projects

**Accepted: Webhook triggers (from Linear)**
Column reacts not only to manual drag-and-drop but also to external events via webhooks. GitHub webhooks as first integration: PR merged → move task, deploy completed → move task.

**Accepted: Filtered views (from GitHub Projects)**
One board, multiple views via Ransack. Filter by assignee, type, tags, priority. Agent gets its own "slice" of the board. Views: "my work", "all bugs", "agent tasks", "current sprint".

**Rejected: Automation rules / if-then (from Jira)**
Not needed — agents are smart enough to handle conditional logic described in workflow step text. Board structure is available via `get_board_info()`.

#### From n8n / Temporal / Zapier

**Noted for future: Durable execution (from Temporal)**
Not implementing full state recovery. Will verify that existing retry mechanism in workflows works correctly for agent failures (rate limits, token limits).

**Already exists + extension: Visual workflow builder (from n8n)**
Manual workflow builder already exists. Adding agent-based builder as system workflow (Framework Importer).

**Rejected: Trigger + Action model (from Zapier)**
Agents can do simple if-then logic themselves via text instructions in workflow steps.

#### From Cursor / Devin

**Accepted for meta-workflow only: Session visualization (from Devin)**
Real-time visualization of what agent is doing — only for system workflows (Framework Importer). For regular workflows — not needed.

**Accepted: Parallel agent sessions (from Cursor background agents)**
Multiple tasks in different columns with auto-triggers launch parallel workflow sessions. Need UI showing that a workflow is in progress for current task: blinking indicator + link to specific workflow run.

#### From Notion / Slack / Discord

**Accepted: Activity feed (inspired by Slack notifications)**
- Activity feed at board level and task level
- Format: "Task X moved by agent (managed by Artem Petrov) from status A to status B"
- Format: "Task X — comment added with tag tech_design"
- Who initiated: human directly, or agent (and which user managed the session)

**Accepted: Column transition history**
Log of task movements between columns with timestamps. Who moved (human / agent / auto-trigger). Foundation for future analytics: time spent in each column, average time per stage, bottleneck detection.

**Accepted: Progress checklist on task card (inspired by GitHub Actions status checks)**
Visual progress indicators on the task card showing completed stages.

---

### Chaos Engineering — Stress Testing

#### Scenario 1: Infinite loop (workflow moves task → auto-trigger → workflow moves back)
**Decision:** Defer. Cooldown is sufficient for now. Good idea for future rate-limiting.

#### Scenario 2: Concurrent access (two workflows writing to same task)
**Decision:** Not possible in current architecture. One task = one column = one workflow at a time.

#### Scenario 3: Runaway agent (spamming create_task)
**Decision:** No rate limiting now. Instead, add session context instructions: use `fail_session` if looping detected, use `request_human_help` if confused. This yielded two new MCP tools (#12, #13).

#### Scenario 4: User skips columns (drags from Backlog to Done)
**Decision:** User freedom. No column transition constraints. User may have valid reasons.

#### Scenario 5: Preset becomes outdated
**Decision:** Already solved — preset detaches on first modification.

#### Scenario 6: Deleted workflow with existing column binding
**Decision:** Prevent deletion if workflow is bound to a column. Only project-scoped workflows can be bound.

#### Scenario 7: Board visual overload (50 stories)
**Decision:** Filtered views via Ransack solve this.

#### Scenario 8: Who is the actor when agent moves task?
**Decision:** Actor = task assignee always (required for authorization in agent runtime). `author_type` in comments separates agent vs human actions.

---

## Implementation Prioritization

### Wave 1: MVP Board
1. Board + Columns model with presets and `purpose` field
2. Tasks CRUD (types, epic↔story relationship)
3. Comments (with tags and author_type)
4. Task assets
5. Basic board UI with drag-and-drop

### Wave 2: Automation
6. Workflow binding to column (auto/manual + cooldown)
7. Internal MCP Tools (13 tools)
8. Activity feed + column transition history
9. Workflow-in-progress indicator on task card

### Wave 3: Advanced Features
10. Filtered views (Ransack)
11. GitHub webhook integration (PR merged → move task)
12. Progress checklist on task card
13. Analytics from transition history (time per column, bottlenecks)

### Wave 4: Wow Effect
14. System workflow type "Framework Importer"
15. Real-time artifact creation visualization

---

## Session Summary and Insights

**Key Achievements:**
- Complete architectural blueprint for AI-powered task board system
- 13 internal MCP tools defined with clear interfaces
- 4-wave implementation roadmap from MVP to wow-effect features
- Edge cases identified and resolved through chaos engineering
- Clear separation of concerns: board is simple, intelligence lives in workflows and agents

**Design Principles Emerged:**
- **YAGNI:** Don't overengineer protections — build when needed
- **Agent intelligence over system rules:** Agents are smart enough to follow text instructions for conditional logic
- **Simplicity in data model, power in tools:** Flat comments with tags beat threaded discussions. Simple columns with purpose fields beat complex state machines.
- **Human freedom:** No artificial constraints on user actions (skip columns, re-run workflows)
- **Single source of truth:** One board per project, board_id auto-resolved, task is the central entity

**Creative Breakthroughs:**
- `purpose` field on columns — turns the board into a self-documenting process for agents
- `fail_session` / `request_human_help` tools — agent self-diagnostic capabilities
- System workflow with real-time artifact visualization — the "wow effect" of watching AI build AI infrastructure
- Activity feed with actor attribution — "agent (managed by User)" format for full transparency
