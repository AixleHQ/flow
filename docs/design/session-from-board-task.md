# Start an Agent Session from a Board Task

**Date:** 2026-08-07
**Status:** Draft — for review (design only, no implementation)
**Board task:** #402 "Start session from task"

---

## Overview

A user should be able to open a board task, press one button, and get an agent
session that already knows the task — its description, comments, column, board
position — and that carries the configuration the task needs (board tools, MCP
servers, repositories, assets). Today the only way to reach that state is to
bind a workflow to the task's column and run it.

This document describes the **general shape** of the feature: the current
coupling that blocks it, the domain-model change it needs, where the resources
come from, the user flow, and the UI entry points. Low-level implementation
detail (migrations, method signatures, test plans) is deliberately out of scope
and belongs in the follow-up spec.

### Related documents

| Document | Why it matters here |
|----------|---------------------|
| [Session Config & Context](./session-config-and-context.md) | The two-stage pipeline (`SessionConfigResolver` → `SessionContextConstructor`) this feature plugs a third session shape into |
| [Workflow Architecture](../architecture/workflows.md) | Workflow / Step / StepRun model and the board auto-trigger path |
| [Tool Execution Strategy](./tool-execution.md) | How platform tools are defined, injected, and served over the per-session MCP endpoint |

---

## 1. Where we are today

### 1.1 Two ways a session gets created

| Path | Entry point | Session record | Task-aware? |
|------|-------------|----------------|-------------|
| **Standalone** | `/company/projects/:id/sessions/new` → `POST /api/v1/terminal_sessions` → `SessionService.create_and_start` | `session_type: "agent_session"`, resources = exactly what the user ticked in the form | **No** |
| **Workflow step** | Task enters a column with a `ColumnWorkflowBinding` (auto), or the task drawer's **Run workflow** button (manual) → `TriggerEngine` → `WorkflowRun` → `StepRun` → `SessionService.create_for_workflow_step` | `session_type: "workflow_step"`, resources resolved by `SessionConfigResolver` | **Yes** |

There is also a third, narrower precedent worth naming: **Aixle Builder**
(`Web::Company::Projects::AixleBuilderController#start`). It is a standalone
`agent_session` launched from a dedicated button with a pre-computed tool set, a
canned initial prompt, injected config files, and a `metadata: { aixle_builder:
true }` marker that `ContextBuilders::AixleBuilder` keys off. It proves the
platform can already launch a *purpose-built* session outside a workflow — what
it does not have is a **relationship to a domain record**.

### 1.2 The single structural cause

Every task-aware behaviour in the platform reaches the task through one path:

```
TerminalSession → StepRun → WorkflowRun → BoardTask → Board
```

`TerminalSession` has no edge to `BoardTask`. `WorkflowRun` does
(`belongs_to :board_task, optional: true`). So "session knows its task" is,
today, a synonym for "session belongs to a workflow run that was triggered from
a task".

### 1.3 What that costs, concretely

Five places encode that assumption. A standalone session hits all five:

| # | Site | Behaviour without a workflow |
|---|------|------------------------------|
| 1 | `ContextBuilders::Base#board_task` → `step_run&.workflow_run&.board_task` | `nil` |
| 2 | `ContextBuilders::BoardContext#applicable?` → `board_task.present?` | Builder never runs — **no task context in the prompt at all** |
| 3 | `Tools::InjectionRules[:workflow_step_session]` → `session_type == "workflow_step"`; every `board_*` tool declares `inject_when :workflow_step_session` | Board tools are never auto-injected |
| 4 | `InternalTools::Base#require_workflow_context!` — raises unless `step_run` is present; called first in every board tool's `execute` | Board tools **fail even when manually attached**. They are `user_attachable` by default and appear in the picker's board group, so a user can tick them today and get a tool that always errors |
| 5 | `SessionConfigResolver#session_type` → `:standalone` when `step_run` is nil; `#board_task` reads the workflow chain | No task/column contribution to the resolved resource set |

Two more downstream consequences follow from the same edge being missing:

- `BoardContextResolver.resolve(session)` falls back to `session.project&.board`,
  so a standalone session can *find a board* but has no notion of **which task**
  it is working on — every board tool call would need an explicit `task_id`.
- Analytics that slice sessions by task (`TaskFilterable#apply_task_filters`,
  `SessionSourceBreakdownService`) join through `StepRun → WorkflowRun →
  board_task_id`, so task-launched sessions would be invisible to them.

---

## 2. Goals and non-goals

**Goals**

1. Start an agent session from a specific board task, without a workflow.
2. The session receives the task's context the same way a workflow-step session
   does (board context section in the agent's context file).
3. The session receives the configuration the task needs — board tools, MCP
   servers, repositories, assets — with sensible defaults the user can adjust.
4. The task ↔ session relationship is durable and navigable in both directions:
   the task shows its sessions, the session shows its task.
5. Existing workflow-driven sessions keep behaving exactly as they do now.

**Non-goals (this iteration)**

- Changing the workflow engine, `ColumnWorkflowBinding`, or the auto-trigger path.
- Multi-step / multi-session orchestration from a task — that is what workflows
  are for.
- Gates. A task session neither creates nor resolves `Gate` records.
- Automatic column movement when a task session finishes. If the agent moves the
  task, it does so through `board_move_task` like any other agent.
- Resolving the long-standing `TaskAsset` → `Asset` gap (see §4.4).

---

## 3. Proposed shape

### 3.1 Domain model: one new edge

```
                         ┌──────────────┐
                         │   Project    │
                         └──────┬───────┘
                                │ 1
                    ┌───────────┴────────────┐
                    │ 1                      │ *
             ┌──────▼──────┐         ┌───────▼─────────┐
             │    Board    │         │ TerminalSession │
             └──────┬──────┘         └───────┬─────────┘
                    │ 1                      │
             ┌──────▼──────┐                 │ has_one
             │ BoardColumn │                 │
             └──────┬──────┘         ┌───────▼─────────┐
                    │ 1              │    StepRun      │
             ┌──────▼──────┐         └───────┬─────────┘
             │  BoardTask  │                 │ belongs_to
             └──────┬──────┘         ┌───────▼─────────┐
                    │  ╲             │  WorkflowRun    │
                    │   ╲ 1..*       └───────┬─────────┘
                    │    ╲                   │ belongs_to (optional)
                    │     ╲__________________│  ← EXISTING indirect path
                    │
                    └───── NEW: BoardTask 1 ──── * TerminalSession
```

**The change:** `TerminalSession belongs_to :board_task, optional: true`
(nullable FK + index), `BoardTask has_many :terminal_sessions, dependent: :nullify`.

**Why a real association rather than the Aixle Builder `metadata` pattern.**
`metadata: { aixle_builder: true }` is right for a *role flag* — a boolean with
no counterpart record. A task binding is a genuine edge in the domain graph and
needs the things only an edge gives:

- the reverse relation (the task drawer lists its sessions, with counts);
- referential integrity and a cheap indexed join for analytics;
- authorization scoping (`task.terminal_sessions.find(...)`);
- board tools that can answer "which task am I on?" without a parameter.

A JSON key would force `metadata @> '{"board_task_id": N}'` lookups in every one
of those places.

**Should a workflow-step session also set `board_task_id`?** Recommended: yes,
backfilled at `create_for_workflow_step` time from `workflow_run.board_task`, so
`session.board_task` is *the* way to ask the question and the `StepRun →
WorkflowRun` walk becomes an implementation detail. This is a small consistency
win and it is what makes the resolver changes in §3.3 collapse to one branch
instead of two. It is separable from the feature and can be deferred.

### 3.2 Task binding vs. `session_type` — a deliberate split

`session_type` currently does one job: it selects the **container strategy**
(`TerminalSession#strategy` → `AgentAuthStrategy` / `AgentSessionStrategy` /
`WorkflowStepStrategy`). A task session runs the *same container as a standalone
agent session* — same image, same credential handling, same interactive/
non-interactive exec, same cleanup.

**Recommendation:** keep `session_type = "agent_session"` and treat the task
binding as an **orthogonal dimension** expressed by `board_task_id` presence.

- No fourth strategy branch, no new validation vocabulary, no migration of the
  `active`/`agent_sessions` scopes.
- `SessionConfigResolver` already has a *logical* session type
  (`:standalone` / `:workflow` / `:board_triggered`) that is separate from the
  DB column. Adding `:task` there is the natural home for the distinction.
- `Tools::Context` gains a `board_task` accessor, and the board tools' injection
  rule becomes "a board task is in scope" instead of "this is a workflow step".

**Alternative considered — `session_type: "task_session"`.** Cleaner for
analytics (`SessionSourceBreakdownService::SOURCE_LABEL` is keyed by
`session_type`, so a new label would come free) and self-documenting in the
admin list. The cost is that `session_type` then means two things at once —
container shape *and* provenance — and every existing branch on it has to be
audited. If reviewers prefer provenance in the column, the rest of this design
is unchanged; only the predicate names move.

Either way the analytics surfaces need a small update to distinguish
"Standalone" from "From a task"; with the recommended option that reads
`board_task_id IS NULL` rather than a new enum value.

### 3.3 Config resolution: resolve at launch, store explicitly

A task session has no `Step` to declare requirements, so the question is where
its tools / skills / MCP servers / repositories come from.

**Sources available:**

| Source | Contributes |
|--------|-------------|
| The workflow bound to the task's current column (`task.board_column.column_workflow_binding.workflow`) | Its `base_tool_ids` / `base_skill_ids` / `base_mcp_server_ids` / `base_asset_ids`, and `inherit_all_project_resources` — the column already declares what work at this stage needs |
| The project | `Tool.visible_for_project`, `Skill.…`, `MCPServer.…`, `Repository.…` |
| The user, in the launch dialog | Additions and removals |
| The board tool group | Injected at serve time, never stored (see §3.5) |

**Recommended rule — the cascade runs once, as a *prefill*:**

```
launch-dialog defaults =
      column-bound workflow base resources        (if the column has a binding)
    + project resources                           (if that workflow sets inherit_all_project_resources)
    + project repositories                        (default on; the user can clear)
  → user reviews and adjusts
  → the resolved set is stored on the session, exactly as a standalone session stores it today
```

This keeps a task session on the **standalone branch** of
`SessionConfigResolver` (read the stored ids off the session record) and puts
the cascade in a small prefill service that the "new session for this task"
screen calls. The reasoning: a workflow step has no human present, so it *must*
resolve late; an interactive launch has a human who should see and be able to
change what the agent is about to get. Late resolution here would mean the
dialog shows one thing and the container gets another.

`SessionConfigResolver` still gains `:task` as a logical session type — it is
what `resolve_with_breakdown` reports for traceability, and what the context
builders and injection rules branch on.

**Runtime and persona.** Runtime follows the existing standalone chain (user
picks; default from the company membership's default credential). Persona
(`configured_agent`): the column-bound workflow has no single agent — its steps
do — so there is nothing sensible to prefill. Leave it to the user's choice in
the dialog, defaulting to none.

### 3.4 Context construction: one predicate change

`SessionContextConstructor` needs no new builder. `ContextBuilders::BoardContext`
already renders exactly the right section — task title, description, column,
priority, tags, assignee, the full column list with the current one marked,
recent comments, and the board tool catalogue. It simply never fires for a
standalone session.

The change is at the base: `ContextBuilders::Base#board_task` resolves the
direct `session.board_task` first and falls back to the workflow chain. Then:

- `BoardContext#applicable?` becomes true for a task session — free.
- `ContextBuilders::SessionInfo` should stop hard-coding "You are running in a
  standalone … session" when a task is bound.
- `ContextBuilders::WorkflowContext` stays gated on `step_run` and correctly
  does not fire — there is no workflow, no step, no sub-steps.

The resulting context for a task session is: critical rules → agent role →
session info → workspace → **board context** → tools → resources → output
rules. That is the workflow-step context minus the workflow/step/sub-step
sections, which is precisely what is wanted.

### 3.5 Tool exposure: two gates to open

Board tools reach the container over the per-session MCP endpoint
(`MCPController` authenticates by `mcp_key` → `Tools::MCPRequestHandler`), so no
new transport or per-session MCP registration is needed. Two gates block them:

1. **Injection.** Replace `inject_when :workflow_step_session` on the `board_*`
   tools with a rule that means "a board task is in scope" — satisfied by a
   workflow-step session (unchanged) *or* by a session with a `board_task`. This
   requires `Tools::Context` to carry the task. `list_sub_steps` / `mark_sub_step`
   keep the workflow-only rule: a task session has no sub-steps.
2. **Execution.** `InternalTools::Base#require_workflow_context!` must become a
   board-context guard for the board tools — "a board is resolvable", not "a
   step_run exists". `BoardContextResolver` gains the direct
   `session.board_task&.board` branch ahead of the workflow walk.

Two smaller follow-ons in the same area:

- Board tools that today default `task_id` from `workflow_run&.board_task_id`
  (e.g. `board_get_task`) should default from the session's bound task instead.
- Board tools that pick an author/actor via `workflow_run&.user` (e.g.
  `board_add_comment`, `board_move_task`) need `session.user` as the fallback,
  otherwise agent comments from a task session have no author.

`finish_session` / `fail_session` are gated on `non_interactive_session` and are
unaffected — they work for a non-interactive task session and are absent from an
interactive one, which is correct.

**MCP servers the task needs.** Beyond the platform board tools, the "task-specific
configuration" in the task description is the MCP-server set. Those come from the
prefill in §3.3 and are attached to the session record like any other resource,
which means the existing OAuth and URL-safety preflights in
`SessionService.create_and_start` apply unchanged — a task session that selects
an unconnected OAuth MCP server gets the same "Connect …" CTA instead of a
silently broken container.

---

## 4. User flow and UI entry points

### 4.1 The flow

```
Board  →  click task  →  task drawer (Details tab)
                              │
                              │  [ ▶ Start session ]        ← new, next to [ ▶ Run workflow ]
                              ▼
                    ┌──────────────────────────────────┐
                    │  Start session — "<task title>"  │
                    ├──────────────────────────────────┤
                    │  Runtime   ( Claude Code  ▾ )    │
                    │  Model     ( default      ▾ )    │
                    │  Mode      (•) Interactive       │
                    │            ( ) One-shot          │
                    │  Prompt    [ prefilled from the  │
                    │              task, editable    ] │
                    │                                  │
                    │  ▸ Resources (prefilled)         │
                    │      Tools / Skills / MCP /      │
                    │      Repositories / Assets       │
                    │                                  │
                    │  Board tools are always on for   │
                    │  a task session.                 │
                    │                        [ Start ] │
                    └──────────────────────────────────┘
                              │
                              ▼
              session page (terminal), with a breadcrumb
              back to the task
                              │
                              ▼
              task drawer → Sessions tab lists it, live state
```

### 4.2 Entry point — the task drawer

`TaskDetailSidebar` (`app/frontend/pages/Projects/Board/BoardPage.tsx:1451`)
already owns the panel bar where **Run workflow** lives, and already gates it on
`canExecute`. **Start session** sits beside it with the same permission gate,
and — unlike **Run workflow** — is *always* available: it needs no
`ColumnWorkflowBinding` and is not blocked by an active workflow run. Concurrent
task sessions are allowed; they are just sessions.

A secondary entry point on the task card's context menu is optional and can
follow later.

### 4.3 The launch dialog

Reuse `SessionNewForm` rather than build a second form — it already handles
runtime selection, configured agents, model, mode, the resource multi-selects,
BMAD, the cost hint, and the OAuth-preflight 422 → "Connect …" rendering. It
needs a task-aware variant of its props: the task title in the header, the
prefilled resource sets from §3.3, and a prefilled initial prompt.

**Prefilled prompt.** Something the user can accept blind or rewrite —
e.g. *"You are working on board task #402 'Start session from task'. The task
description and recent comments are in your context. Ask me what to do first."*
The prompt is required for one-shot mode (`validates :initial_prompt, presence:
true, if: mode == "non_interactive"`) and optional for interactive.

**Where it renders.** A modal over the board keeps the user in place and is the
better default; the alternative is routing to the existing full-page
`Projects/Sessions/NewPage` with the task pre-bound. The modal is recommended —
starting a session from a task should feel like an action on the task, not a
navigation away from the board.

### 4.4 What the user sees afterwards

- **Redirect** to the session page (`Projects/Sessions/ShowPage`) with the live
  terminal, plus a breadcrumb / back-link to the originating task.
- **A new "Sessions" tab in the task drawer**, alongside Runs / Comments /
  Assets / Activity / Analytics: every session started from this task, with
  state badge, runtime, cost, duration, and a link. It is the reverse relation
  from §3.1 made visible, and it is the reason a real FK earns its keep.
- **Board activity.** A `board_activities` entry ("session started") keeps the
  task's audit trail complete, consistent with how `TaskService` records
  triggers and moves.
- **Session lists** (project and company) gain a task chip on rows that have
  one, so the connection is visible from the session side too.

**Task assets.** `TaskAsset` is a Shrine upload, not a reference to `Asset` —
the same gap that keeps `SessionConfigResolver#board_task_asset_ids` stubbed to
`[]` for board-triggered workflow runs. A task session inherits that gap: files
attached to the task are described by `board_get_task_assets` but are not mounted
into the workspace. Out of scope here; it is one shared fix that lands for both
paths at once.

---

## 5. Entities and relationships — summary

| Entity | Role in this feature | Change |
|--------|---------------------|--------|
| `BoardTask` | The context anchor: title, description, tags, priority, assignee, column, comments | `has_many :terminal_sessions, dependent: :nullify` |
| `TerminalSession` | The agent run | `belongs_to :board_task, optional: true` (new nullable FK + index) |
| `Board` / `BoardColumn` | Board tools scope every call to the task's board; the column is what the agent moves the task between | — |
| `ColumnWorkflowBinding` → `Workflow` | Read-only here: the source of the resource **prefill** in §3.3 | — |
| `WorkflowRun` / `StepRun` | The existing indirect path; unchanged. Optionally also sets `board_task_id` on its session (§3.1) | — |
| `Project` / `Company` | Tenancy and resource visibility; already carried by the session | — |
| `Tool` / `Skill` / `MCPServer` / `Repository` / `Asset` | Attached to the session by the existing HABTM joins | — |
| `Gate` | Explicitly untouched | — |

**Cardinality:** one task → many sessions; one session → at most one task. A
session's task must belong to the session's project — enforced as a validation,
since the two FKs are independent.

---

## 6. Authorization, tenancy, lifecycle

- **Permission.** Same gate as any session launch: `canExecute` on the front
  end, the viewer check in `Api::V1::TerminalSessionsController#create` on the
  back end. Reachability of the task is checked through the project the user
  already has access to.
- **Tenancy.** `company_id` comes from the task's project, exactly as it does
  for a project-bound standalone session. `SessionCompany` and the per-company
  credential rule are unchanged — a task session bills the company that owns the
  board.
- **Lifecycle.** Identical to a standalone `agent_session`: `not_started →
  running → ready → finishing → finished`, driven by the same Temporal
  container workflow. Nothing in the workflow engine observes it, so there is no
  `WorkflowService.notify_container_finished` equivalent to wire.
- **Task deletion.** `dependent: :nullify` — the session and its logs, assets,
  and cost records survive; they simply lose the link.

---

## 7. Decisions to confirm in review

1. **`board_task_id` FK vs. `metadata`** — recommended: FK (§3.1).
2. **`session_type: "agent_session"` + task binding vs. a new `"task_session"`
   type** — recommended: keep `agent_session`, but analytics labelling is the
   one place the alternative is cleaner (§3.2).
3. **Prefill-and-store vs. resolve-at-run for resources** — recommended:
   prefill and store, because a human is present (§3.3).
4. **Modal on the board vs. routing to the full new-session page** —
   recommended: modal (§4.3).
5. **Backfill `board_task_id` on workflow-step sessions** — recommended, but
   separable (§3.1).
6. **One task, many concurrent sessions** — recommended: allowed, unlike
   workflow runs which are serialised per task.

## 8. Deferred

- `TaskAsset` → `Asset` unification, so task attachments mount into the
  workspace for both this path and board-triggered workflow runs (§4.4).
- Starting a session from a task **card** context menu, and from outside the
  board (e.g. a task link in Slack).
- Suggesting a prompt from the task's column purpose (`BoardColumn#purpose`).
- Surfacing task sessions in the task Analytics tab's cost roll-up alongside
  workflow runs.
