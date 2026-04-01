---
stepsCompleted: ['step-01-init', 'step-02-discovery', 'step-02b-vision', 'step-02c-executive-summary', 'step-03-success', 'step-04-journeys', 'step-05-domain', 'step-06-innovation', 'step-07-project-type', 'step-08-scoping', 'step-09-functional', 'step-10-nonfunctional', 'step-11-polish', 'step-12-complete']
inputDocuments:
  - '_bmad-output/brainstorming/brainstorming-session-2026-02-26.md'
  - 'ai/project-context.md'
  - 'ai/prd/index.md'
  - 'ai/prd/functional-requirements.md'
  - 'ai/prd/product-scope.md'
  - 'ai/prd/project-scoping-phased-development.md'
workflowType: 'prd'
documentCounts:
  briefs: 0
  research: 0
  brainstorming: 1
  projectDocs: 4
classification:
  projectType: 'saas_b2b'
  domain: 'internal_service_company'
  complexity: 'medium'
  projectContext: 'greenfield'
---

# Product Requirements Document — Board & Tasks

**Author:** Artem_petrov
**Date:** 2026-02-26
**Parent PRD:** [Aixle PRD](./index.md)

## Executive Summary

AIXLE is an AI-agent orchestration platform for service companies. Board & Tasks is a semi-automated development module where the task board acts as a control panel for the SDLC process. Columns are development stages, workflow triggers are the executors. A human defines the automation boundary: which stages the agent handles on its own (`auto`), and where manual control is required (`manual`).

A task moves across the board — from backlog to done. On each transition the system can launch an attached workflow: tech design, code review, QA. Agents interact with tasks through 13 internal MCP tools: they read context, write tagged comments, attach artifacts, and move tasks. Tagged comments (`tech_design`, `code_review`, `feedback`) are the feedback channel between human and agent.

Target users: developers and tech leads at a service company using AIXLE to automate the SDLC.

### What Makes This Special

The built-in board is a first-class citizen of the system, not an integration with an external tracker. Moving a task is not just a status change but a trigger for an AI agent. The human decides where they matter: setting `manual` on stages they want to control, `auto` where they trust the agent. The Board is simple (columns + purpose field), the intelligence lives in workflows and agents. This is not Jira with an AI assistant — it is the interface between a human and the AI development pipeline.

## Project Classification

| Parameter | Value |
|---|---|
| **Project Type** | SaaS B2B |
| **Domain** | Internal (service company tooling) |
| **Complexity** | Medium |
| **Project Context** | Greenfield (built from scratch with BMAD) |
| **Parent System** | AIXLE — AI agent orchestration platform |

## Success Criteria

### User Success

- A user creates a board with a preset and configures columns for their process in < 5 minutes
- Moving a task into a column with an `auto` trigger starts the linked workflow with no additional user actions
- A developer sees the result of the agent's work (a tagged comment) on the task within the workflow's execution time, without switching to another interface
- A tech lead defines the automation boundary: sets `manual` on stages requiring control, `auto` where they trust the agent, and changes the configuration at any time
- Through MCP tools, the agent gets the full task context (description, comments, assets) and board structure without additional configuration — `board_id` is determined automatically from the session context

### Business Success

- Board & Tasks replaces the need for Linear/Jira for the team's internal projects within the first 4 weeks after the MVP launch
- 80% of workflow runs linked to columns complete successfully (without `fail_session`) during the first month of use
- Time from idea to working code is reduced by at least 30% thanks to automatic triggers at the tech design → implementation → code review stages
- A team of 3 uses the board daily as the primary task management interface for 2 weeks after deployment

### Technical Success

- Cooldown prevents double-triggering on drag-and-drop jitter: no more than 1 workflow run per task move
- 13 MCP tools (5 read, 6 write, 2 self-diagnostic) are available to the agent in the workflow session context without manual configuration
- Column transition history records every move with a timestamp, actor (human/agent/auto-trigger), and source/target column
- Parallel workflow sessions for tasks in different columns work without conflicts — one task = one column = one active workflow at a time
- The activity feed reflects events in real time via ActionCable

### Measurable Outcomes

| Metric | Target | Measurement |
|--------|--------|-------------|
| Board setup time | < 5 min from preset selection to first task | Manual testing |
| Workflow trigger latency | < 3 sec from task move to workflow start | Temporal metrics |
| Agent context resolution | 100% auto-resolved board_id | Automated test |
| MCP tool availability | 13/13 tools functional in workflow sessions | Integration tests |
| Comment-based feedback loop | Agent reads previous comments with tag filter in < 1 sec | API response time |
| Double-trigger prevention | 0 duplicate runs per 100 task moves | Production logs |

## Product Scope

| Phase | Key Features |
|-------|--------------|
| **MVP (Wave 1-2)** | Board + Columns with presets, Tasks CRUD (types, epic→story), Comments with tags, Task assets, Drag-and-drop UI, Workflow binding (auto/manual + cooldown), 13 MCP tools |
| **Growth (Wave 2-3)** | Activity feed, Column transition history, Filtered views (Ransack), GitHub webhooks, Progress checklist |
| **Vision (Wave 4+)** | Framework Importer system workflow, Analytics (time per column, bottlenecks), Board templates marketplace |

> For the detailed roadmap, feature priorities, and risk mitigation, see [Project Scoping & Phased Development](#project-scoping--phased-development)

## User Journeys

### Journey 1: Tech Lead Katya — Board Setup & Process Design

**Persona:** Katya, 35, tech lead. She wants to set up the SDLC process so that routine stages (tech design, code review) are performed by agents automatically, while she controls only the key checkpoints.

**Opening Scene:**
A new project in AIXLE. Katya creates a board to track tasks. She used to use Linear, but she wants moving a task to start the right workflow on its own.

**Rising Action:**
1. Katya creates a Board, selects the "Full SDLC" preset → gets the columns: Backlog, Tech Design, Implementation, Code Review, QA, Done
2. Edits the columns: adds "Estimation" between Backlog and Tech Design, removes QA (not needed yet)
3. For each column she fills in `purpose` — a description for the agent: "Technical design is being created. Expected output: comment with tag tech_design"
4. Links workflows to columns:
   - Tech Design → workflow "Create Tech Design" (mode: `auto`)
   - Implementation → workflow "Implement Feature" (mode: `manual` — she wants to choose the agent herself)
   - Code Review → workflow "Review Code" (mode: `auto`)
5. Creates the first tasks: epic "User Authentication", stories "Login API", "OAuth Integration", "Session Management"

**Climax:**
Katya drags the "Login API" story into the Tech Design column. The system automatically starts the linked workflow. An indicator appears on the task card — workflow in progress. After 5 minutes the agent leaves a comment with the tag `tech_design` — a finished technical design. Katya reads it and writes a comment with the tag `feedback`: "Add rate limiting section". She drags the task back into Tech Design — the workflow starts again, the agent reads the feedback and refines the design.

**Resolution:**
- The board is set up in 5 minutes
- The process is self-documented through the `purpose` field
- Automation works: move = trigger
- The feedback loop via tagged comments closes the human↔agent cycle

---

### Journey 2: Developer Misha — Daily Task Execution

**Persona:** Misha, 28, mid-level developer. Works with tasks on the board, uses the board as the primary interface.

**Opening Scene:**
Morning, Misha opens AIXLE. On the board in the Implementation column there are 3 tasks assigned to him. For one of them a tech design is already ready (a comment with the tag `tech_design` from the agent).

**Rising Action:**
1. Misha opens the "Login API" task → sees the tech design in the comments, assets (ER diagram)
2. The Implementation column is configured as `manual` — Misha clicks "Start Workflow" himself
3. An interactive session with the agent starts; through MCP tools the agent reads the task context: description, tech design, related assets
4. Misha works with the agent, clarifying details
5. The agent adds a comment with the tag `implementation_notes` and attaches an asset (generated files)

**Climax:**
The work is done. Misha drags the task into Code Review. The `auto` trigger starts the review workflow. The reviewer agent reads the code changes and tech design, and leaves a comment with the tag `code_review`.

**Resolution:**
- Misha sees the review result on the task — without switching between interfaces
- If everything is fine — he drags it into Done
- If there are comments — back into Implementation with feedback, and the cycle repeats

---

### Journey 3: Senior Developer Sasha — Batch Automation

**Persona:** Sasha, 32, senior developer. Trusts the agents, wants maximum automation.

**Opening Scene:**
In the backlog there are 8 stories from the epic "Payment Integration". All with a tech design. Sasha wants to run them "on a conveyor" — without manual control.

**Rising Action:**
1. Sasha selects 8 tasks and drags them into the Implementation column (all `auto`)
2. The system starts parallel workflow sessions for each task
3. On each card — a progress indicator with a link to the workflow run
4. Sasha goes to a meeting

**Climax:**
After 30 minutes Sasha returns. The activity feed shows: 6 tasks moved into Code Review (the auto-trigger worked), 1 task — the agent called `request_human_help("Ambiguous requirement: should payment retry be synchronous or async?")`, 1 task — the agent called `fail_session("Token limit exceeded")`.

**Resolution:**
- 6 tasks automatically passed implementation + code review
- 1 task is waiting for Sasha's reply — he writes a comment with the tag `feedback`, and the workflow continues
- 1 failed task — Sasha sees the cause, reduces scope, and restarts

---

### Journey 4: Admin Andrey — Board Template & Workflow Binding

**Persona:** Andrey, co-founder. Sets up the standard process for the team.

**Opening Scene:**
The team has grown to 5 people. A unified process is needed: identical boards, identical workflow bindings, identical rules.

**Rising Action:**
1. Andrey creates a "reference" board in the Demo project: columns, purposes, workflow bindings
2. For each column he configures: which workflow, auto or manual, cooldown
3. Verifies that a workflow bound to a column cannot be deleted (the system blocks it)
4. Creates workflows at the company level — they are available for binding across all projects

**Resolution:**
- The standard process is documented in the board structure
- New projects are created from the template
- The `purpose` field on columns — built-in process documentation for agents and humans

---

### Journey 5: Agent (System Actor) — Autonomous Task Processing

**Persona:** AI Agent, a running workflow session. Interacts with the board through 13 MCP tools.

**Opening Scene:**
The "Create Tech Design" workflow is launched by an auto-trigger when a task is moved to the Tech Design column.

**Rising Action:**
1. The Agent calls `get_board_info()` — gets the board structure and the purpose of the current column
2. The Agent calls `get_task(task_id)` — gets the task description, type, priority, and linked epic
3. The Agent calls `get_comments(task_id, tag: "feedback")` — checks whether there is feedback from a human (if the task was returned for rework)
4. The Agent calls `get_task_assets(task_id)` — loads the linked files
5. The Agent does the work: generates the tech design
6. The Agent calls `add_comment(task_id, body: tech_design_content, tags: ["tech_design"])` — publishes the result
7. The Agent calls `attach_asset(task_id, file: diagram, tags: ["architecture"])` — attaches the artifact
8. The Agent calls `move_task(task_id, column_name: "Implementation")` — moves the task forward

**Edge case — Agent stuck:**
The Agent calls `request_human_help("Task description is ambiguous: does 'user' mean end-user or admin?")` — the session is paused, with a notification on the task.

**Edge case — Agent looping:**
The Agent detects a loop → calls `fail_session("Detected loop in tech design generation after 3 attempts")` — the session ends, the task stays in the current column.

**Resolution:**
- The task is moved to the next column with full context: tech design + assets
- A human can read the result and give feedback
- If the agent failed — transparent diagnostics via `fail_session`/`request_human_help`

---

### Journey 6: PM Lena — Board Analytics & Monitoring

**Persona:** Lena, 30 years old, PM. Tracks the team's progress.

**Opening Scene:**
A fixed-bid project in its 3rd month. She needs to understand: where the bottleneck is, whether they are on timeline.

**Rising Action:**
1. Lena opens the board → sees the distribution of tasks across columns
2. Uses a filtered view: "All bugs" — sees that 5 bugs are stuck in Code Review
3. Opens the activity feed — sees that over the last 24 hours 12 tasks passed through auto-triggered workflows
4. Checks the column transition history: average time in Tech Design — 8 minutes (agent), in Code Review — 12 minutes (agent), in Implementation — 2 hours (human + agent mixed)

**Resolution:**
- The bottleneck is visible: Implementation — the only manual stage
- Decision: discuss with Katya whether Implementation can be switched to `auto` for simple stories
- Data for the client: a transparency report with a timeline by stage

---

### Journey Requirements Summary

| Journey | Revealed Capabilities |
|---------|----------------------|
| Katya — Board Setup | Board presets, column customization, purpose field, workflow binding (auto/manual), task CRUD, epic→story hierarchy |
| Misha — Daily Execution | Task detail view, comment reading by tag, manual workflow trigger, drag-and-drop, workflow-in-progress indicator |
| Sasha — Batch Automation | Multi-task move, parallel workflow sessions, activity feed, `request_human_help` handling, `fail_session` visibility |
| Andrey — Admin Setup | Company-level workflows, workflow deletion protection, board template creation |
| Agent — Task Processing | 13 MCP tools, auto board_id resolution, comment tags, asset attachment, self-diagnostic tools |
| Lena — Analytics | Filtered views, activity feed, column transition history, time-per-column analytics |

## Domain-Specific Requirements

### Data Integrity & Consistency

| Constraint | Requirement |
|------------|-------------|
| **Task state consistency** | One task = one column at any point in time. Drag-and-drop + auto-trigger must not create a race condition |
| **Workflow binding integrity** | A workflow bound to a column cannot be deleted. Validation on delete |
| **Comment immutability** | Comments are not editable after creation (append-only). Guarantees the integrity of the feedback loop |
| **Transition history completeness** | Every task move is recorded in the log. A lost record = lost data for analytics |

### Authorization & Actor Attribution

| Constraint | Requirement |
|------------|-------------|
| **Agent acts as assignee** | When an agent moves a task / creates a comment — actor = task assignee (for Pundit authorization). The `author_type` field separates agent vs human actions |
| **Project-scoped board** | One board per project. The board inherits project access controls — no separate authorization is needed |
| **MCP tool authorization** | board_id is determined from the session context, not passed by the agent. The agent cannot access another board |

### Concurrency & Trigger Safety

| Constraint | Requirement |
|------------|-------------|
| **Cooldown mechanism** | A minimum interval between triggers for the same task in the same column. Prevents double-triggering from drag-and-drop jitter |
| **No transition constraints** | A user can drag a task into any column (skip columns). The system does not restrict the order of transitions |
| **Parallel session isolation** | Different tasks in different columns launch independent workflow sessions. No shared state between sessions |

### Integration with Existing System

| Constraint | Requirement |
|------------|-------------|
| **Workflow engine reuse** | Board triggers use the existing Temporal-based workflow engine. Do not duplicate execution logic |
| **Asset system reuse** | Task assets use the existing Shrine + S3 infrastructure. The new model — an attachment to a task |
| **MCP tool registration** | 13 board tools are registered as internal tools with `workflow_only: true`. Visible only in workflow sessions bound to columns |

## Innovation & Novel Patterns

### Detected Innovation Areas

**1. Board as AI Orchestration Interface**
Traditional boards (Jira, Linear, GitHub Projects) are tools for people. AI integrations are added as plugins on top. Board & Tasks inverts the approach: the board is designed as the interface between a human and the AI pipeline. Moving a task is not just a status change, but a command to the system to launch a workflow.

**2. Self-Documenting Process via `purpose` Field**
A column contains a `purpose` — a text description of what happens at this stage and what is expected from the agent. Through `get_board_info()` the agent reads the purpose and understands the context without an additional prompt. The board becomes executable process documentation.

**3. Agent Self-Diagnostic Tools**
`fail_session(reason)` and `request_human_help(question)` — the agent does not just crash with an error, but explicitly signals: "I'm stuck, here's why" or "I need human help, here's the question". A pattern from the chaos engineering brainstorming session.

**4. Tag-Based Feedback Loop**
Tagged comments (`tech_design`, `feedback`, `code_review`) replace threading. The agent reads `get_comments(task_id, tag: "feedback")` — getting only the relevant feedback. A simple data model, a powerful interaction pattern.

### Market Context & Competitive Landscape

| Product | Approach | Difference |
|---------|----------|------------|
| **Jira + AI plugins** | AI as an assistant on top of the existing UI | Board & Tasks: AI is a first-class participant, the board is designed for agent interaction |
| **Linear Auto** | AI suggests actions, the human confirms | Board & Tasks: auto-trigger launches a workflow without confirmation, the human stays in control via auto/manual configuration |
| **GitHub Copilot Workspace** | AI generates code from an issue | Board & Tasks: a full SDLC pipeline (design → implement → review), not just code generation |
| **Devin / Cursor Background** | Autonomous agent sessions | Board & Tasks: the board as a control plane for many parallel agent sessions with a feedback loop |

### Validation Approach

1. **Dogfooding:** A team of 3 people uses Board & Tasks for AIXLE's own development in the first month after MVP
2. **Feedback loop effectiveness:** Measure the number of "agent output → human feedback → agent revision" cycles until an acceptable result
3. **Auto vs Manual ratio:** Track what % of columns the team leaves in `auto` vs `manual` — an indicator of trust in the agents
4. **Purpose field utility:** Verify that agents use the purpose field for context (via MCP tool call logs)

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| **Agents can't handle auto-triggered tasks** | Start with `manual` by default, switch to `auto` as trust grows |
| **Purpose field ignored by agents** | Include purpose in the workflow session system prompt, not only via the MCP tool |
| **Feedback loop doesn't close** | Add a notification on a new feedback comment to restart the agent |
| **Board overloaded for simple projects** | A Simple Kanban preset without workflow bindings — works as an ordinary board |

## SaaS B2B — Board & Tasks Specific Requirements

### Project-Type Overview

Board & Tasks is a module inside the existing AIXLE SaaS B2B platform. Multi-tenancy, RBAC, and the subscription model are defined at the parent PRD level. This section specifies how the existing B2B patterns apply to the board module.

### Multi-Tenancy Model

| Aspect | Implementation |
|--------|---------------|
| **Board isolation** | One board per project. A project belongs to a company. Data is isolated through the `company_id` → `project_id` → `board_id` chain |
| **Task isolation** | Tasks, comments, and assets inherit the project scope. The agent sees only the tasks of its project via an auto-resolved board_id |
| **Workflow binding scope** | Only project-scoped workflows are bound to columns. Company-level workflows are copied into the project before binding |
| **Cross-project visibility** | None. Each board is an isolated unit. There are no cross-project board views |

### Permission Model (RBAC)

| Role | Board Permissions |
|------|------------------|
| **Admin** | Full access: create/delete board, manage columns, configure workflow bindings, manage presets |
| **Collaborator** | Task CRUD, move tasks, comments, view board. Cannot modify board structure or workflow bindings |
| **Agent (system)** | MCP tools only: read/write tasks, comments, assets within session scope. Acts as task assignee for authorization |

### Subscription Tiers (Board Impact)

| Tier | Board Limits |
|------|-------------|
| **Free / Internal** | 1 board per project, unlimited tasks, manual triggers only |
| **Pro** | 1 board per project, unlimited tasks, auto + manual triggers, activity feed |
| **Enterprise** | 1 board per project, unlimited tasks, full feature set, analytics, webhook triggers |

### Integration Architecture

| Integration | Board & Tasks Interaction |
|-------------|--------------------------|
| **Temporal** | Workflow triggers create Temporal workflow executions. Board → column move → Temporal signal |
| **ActionCable** | Real-time updates: task moves, new comments, workflow status changes broadcast to board UI |
| **Shrine + S3** | Task assets stored via existing asset pipeline. New `TaskAsset` model with Shrine uploader |
| **MCP (ActionMCP)** | 13 board tools registered as internal MCP tools. Available in workflow sessions via existing MCP infrastructure |

### Implementation Considerations

- **Existing model reuse:** Asset, Workflow, WorkflowRun models already exist. Board adds new models (Board, Column, Task, TaskComment, TaskAsset, ColumnTransition) and extends existing ones
- **No new infrastructure:** Board uses existing Temporal, ActionCable, S3, MCP. No new services required
- **Migration path:** Board does not replace any existing functionality. Additive feature — no breaking changes

## Project Scoping & Phased Development

### MVP Strategy & Philosophy

**MVP Approach:** Experience + Platform MVP
- Full UX for the core board workflow (create board → configure → move tasks → see agent results)
- Extensible via the existing workflow engine and MCP tools
- Internal tool first (one team of 3 people — dogfooding)

**Resource Requirements:** A team of 3 people. Board & Tasks is an additive feature, it does not block current development. Estimate: 4-6 weeks for the MVP (Wave 1 + partial Wave 2).

### MVP Feature Set (Wave 1 + partial Wave 2)

**Core User Journeys Supported:**
- ✅ Katya — Board Setup & Process Design (fully)
- ✅ Misha — Daily Task Execution (fully)
- ✅ Agent — Autonomous Task Processing (fully)
- ⏳ Andrey — Admin Setup (basic: workflow binding, without templates)
- ⏳ Sasha — Batch Automation (partially: parallel sessions work, but without an activity feed)
- ❌ Lena — Analytics (only the basic board view, without filtered views and analytics)

**Must-Have Capabilities:**

| Feature | Priority | Justification |
|---------|----------|---------------|
| Board + Columns model with presets | P0 | Without a board there is no product |
| Column `purpose` field | P0 | Key differentiator — agent context |
| Tasks CRUD (types, epic→story) | P0 | The core entity |
| Flat comments with tags and author_type | P0 | Human↔agent feedback loop |
| Task assets | P0 | Agent output artifacts |
| Drag-and-drop board UI | P0 | Core interaction |
| Workflow binding to a column (auto/manual) | P0 | Core automation mechanism |
| Cooldown on trigger | P0 | Prevention of double-trigger |
| 13 internal MCP tools | P0 | Agent interaction with the board |
| Workflow-in-progress indicator | P1 | UX: it's visible that the agent is working |

### Post-MVP Features (Wave 2 completion + Wave 3)

| Feature | Trigger for Development |
|---------|------------------------|
| Activity feed (board + task level) | After stable use of the MVP for 2+ weeks |
| Column transition history | After the activity feed (shared infrastructure) |
| Filtered views (Ransack) | When there are > 20 tasks on the board and navigation becomes difficult |
| GitHub webhook integration | After the manual workflow for PR review is validated |
| Progress checklist on the card | User demand |
| Workflow-in-progress with link to run | After the MVP indicator |

### Vision Features (Wave 4 + Future)

| Feature | Prerequisite |
|---------|--------------|
| System workflow "Framework Importer" | Stable workflow engine + board MCP tools |
| Real-time artifact creation visualization | Framework Importer workflow |
| Analytics (time per column, bottlenecks) | Column transition history (Wave 2) |
| External webhook triggers | GitHub webhook integration proven |
| Board templates marketplace | Multiple projects using boards |

### Risk Mitigation Strategy

**Technical Risks:**

| Risk | Probability | Mitigation |
|------|-------------|------------|
| MCP tools don't cover the agents' needs | Low | 13 tools defined from brainstorming with chaos engineering. Extensible — new ones can be added |
| Race condition on drag-and-drop + auto-trigger | Medium | Cooldown + database-level locking on task.column_id update |
| Workflow engine can't handle parallel board-triggered runs | Low | Temporal already supports parallelism. The board adds only the trigger mechanism |

**Market Risks:**

| Risk | Mitigation |
|------|------------|
| The team will prefer Linear/Jira | Dogfood the first month. The board must be simpler, not more complex than existing tools |
| Agent quality insufficient for auto-trigger | Start with `manual` by default. `auto` is opt-in as trust grows |

**Resource Risks:**

| Risk | Mitigation |
|------|------------|
| 4-6 weeks too optimistic | Wave 1 (board + tasks + UI) is separated from Wave 2 (automation). Wave 1 can be deployed as a simple board |
| Scope creep in MCP tools | Strictly 13 tools from brainstorming. New ones — only after the MVP is validated |

## Functional Requirements

### Board Management

- **FR1:** User can create a board for a project by selecting a preset (Simple Kanban, Dev Team, Full SDLC)
- **FR2:** User can add, remove, rename, and reorder columns on the board
- **FR3:** User can set a `purpose` text on each column describing the column's role for agents and humans
- **FR4:** System detaches preset after first column modification — board lives independently
- **FR5:** System enforces one board per project

### Column-Workflow Binding

- **FR6:** User can bind a project-scoped workflow to a column
- **FR7:** User can configure trigger mode per binding: `auto` (fires on task entry) or `manual` (user clicks to start)
- **FR8:** System applies cooldown after trigger to prevent duplicate runs from drag-and-drop jitter
- **FR9:** System prevents deletion of a workflow that is bound to a column
- **FR10:** System automatically starts bound workflow when task enters column with `auto` trigger
- **FR11:** User can manually start bound workflow for columns with `manual` trigger

### Task Management

- **FR12:** User can create tasks with title, description, assignee, tags, priority, and task_type (epic, story, bug, not_specified)
- **FR13:** User can create epic→story relationships between tasks
- **FR14:** User can move tasks between columns via drag-and-drop
- **FR15:** User can move tasks to any column without transition constraints
- **FR16:** User can edit and delete tasks
- **FR17:** User can assign tasks to project collaborators
- **FR18:** System maintains one task in exactly one column at any point in time

### Comments & Feedback Loop

- **FR19:** User can add comments to tasks
- **FR20:** User can attach tags to comments (`tech_design`, `code_review`, `qa_report`, `feedback`, custom)
- **FR21:** System records `author_type` (human, agent, system) on each comment
- **FR22:** Comments are append-only — cannot be edited after creation
- **FR23:** User can filter comments by tag and/or author_type

### Task Assets

- **FR24:** User can attach files to tasks
- **FR25:** Agent can attach files to tasks via MCP tool
- **FR26:** User can view and download task assets
- **FR27:** User can tag assets for categorization

### Board UI

- **FR28:** User can view board with columns and task cards in Kanban layout
- **FR29:** User can drag-and-drop task cards between columns
- **FR30:** System displays workflow-in-progress indicator on task card when bound workflow is running
- **FR31:** System updates board in real-time when tasks are moved, comments added, or workflows complete (via ActionCable)

### Internal MCP Tools (Agent Interaction)

**Read tools:**
- **FR32:** Agent can list tasks with filtering by column, tag, task_type, assignee via `list_tasks`
- **FR33:** Agent can get full task details via `get_task`
- **FR34:** Agent can get comments with filtering by tag and author_type via `get_comments`
- **FR35:** Agent can get task assets with filtering by tag via `get_task_assets`
- **FR36:** Agent can get board structure (columns, purposes, workflow bindings) via `get_board_info`

**Write tools:**
- **FR37:** Agent can create tasks via `create_task`
- **FR38:** Agent can update task fields via `update_task`
- **FR39:** Agent can move tasks to a column via `move_task`
- **FR40:** Agent can add comments with tags via `add_comment` (author_type: agent auto-set)
- **FR41:** Agent can attach files to tasks via `attach_asset`
- **FR42:** Agent can manage tags on entities via `add_tag` / `remove_tag`

**Self-diagnostic tools:**
- **FR43:** Agent can terminate session with error reason via `fail_session`
- **FR44:** Agent can pause session and request human input via `request_human_help`

**Context resolution:**
- **FR45:** System auto-resolves board_id from workflow session context — agent never passes board_id explicitly

### Activity & History (Post-MVP)

- **FR46:** User can view activity feed at board level showing task movements, comments, and workflow events
- **FR47:** User can view activity feed at task level showing task-specific events
- **FR48:** System records column transition history with timestamp, actor (human/agent/auto-trigger), source and target column
- **FR49:** Activity feed attributes actions to actor: "agent (managed by [User Name])" format

### Filtered Views (Post-MVP)

- **FR50:** User can filter board view by assignee, task_type, tags, and priority
- **FR51:** User can save named filter presets ("my work", "all bugs", "agent tasks")

## Non-Functional Requirements

### Performance

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Board page load | < 2 sec for board with up to 100 tasks | Browser performance API |
| Drag-and-drop response | < 200ms visual feedback on task move | UI interaction metrics |
| Workflow trigger latency | < 3 sec from task column change to Temporal workflow start | Temporal metrics |
| MCP tool response time | < 1 sec for read tools (`get_task`, `get_comments`, `get_board_info`) | API response time |
| Real-time update delivery | < 500ms from server event to board UI update via ActionCable | WebSocket metrics |
| Comment filtering by tag | < 500ms for tasks with up to 200 comments | API response time |

### Reliability

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Task state consistency | Zero race conditions on concurrent column moves | Integration tests + database constraints |
| Cooldown effectiveness | 0 duplicate workflow runs per 100 task moves | Production logs |
| Transition history completeness | 100% of task moves recorded in history log | Audit comparison: moves vs history records |
| Comment immutability | No API endpoint for comment edit/delete | API surface audit |
| Workflow binding protection | 100% prevention of bound workflow deletion | Integration tests |

### Security

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Board data isolation | Agent cannot access boards outside session's project scope | Automated security tests |
| Auto-resolved board_id | board_id determined from session context, never accepted as agent input | Code review + MCP tool schema audit |
| Actor attribution integrity | All agent actions attributed to task assignee for Pundit authorization, with `author_type` field preserving true actor | Integration tests |
| Project access inheritance | Board access controlled by existing project RBAC — no separate board permissions | Pundit policy tests |

### Integration

| Requirement | Target | Measurement |
|-------------|--------|-------------|
| Temporal workflow trigger | Board column move triggers Temporal workflow within 3 sec | End-to-end integration test |
| ActionCable broadcast | Board events broadcast to all connected project members | WebSocket integration test |
| MCP tool registration | 13 board tools available in workflow sessions without manual configuration | Session startup integration test |
| Shrine/S3 asset storage | Task assets stored and retrievable via existing asset pipeline | Upload/download integration test |
