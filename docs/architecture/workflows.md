# Workflow Engine

**Date:** 2026-02-13 (v3) · **Previous versions:** v2 2026-02-13, v1 2026-01-30
**Status:** Approved
**Author:** Artem Petrov + AI Analysis

Architecture of the workflow and asset system for Aixle. This document defines how
workflows, steps, sub-steps, assets, and their execution are modeled, scoped, and
connected — from high-level concepts and scope rules down to the detailed data
models, execution lifecycle, internal tools, and asset versioning.

Key design principle: **Aixle is a persistent BMAD runtime** — BMAD today works
through fresh LLM chats with markdown files; Aixle turns this into a persistent
system with tracking, assets, versioning, and automation.

| Document | Description |
|----------|-------------|
| [Architecture index](./index.md) | Core architecture decisions, tech stack |

---

## Table of Contents

- [Key Concepts](#key-concepts)
- [Scope Decision](#scope-decision)
- [Implementation Phases & Dependency Graph](#implementation-phases--dependency-graph)
- [1. Core Concepts](#1-core-concepts)
- [2. Data Model](#2-data-model)
- [3. Workspace Structure](#3-workspace-structure)
- [4. Execution Flow](#4-execution-flow)
- [5. Workflow Context Injection](#5-workflow-context-injection)
- [6. Internal Tools (Workflow-specific)](#6-internal-tools-workflow-specific)
- [7. Asset Versioning](#7-asset-versioning)
- [8. Asset Public Sharing](#8-asset-public-sharing)
- [9. Validation](#9-validation)
- [10. BMAD Mapping](#10-bmad-mapping)
- [11. GitHub Integration](#11-github-integration)
- [12. Open Questions — Decisions](#12-open-questions--decisions)
- [13. Implementation Notes](#13-implementation-notes)

---

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Agent** | LLM configuration (persona, system prompt). Not tied to a workflow |
| **Workflow** | Process definition: steps, inputs, outputs. Belongs to one project (polymorphic `scope`: `Project`, or `System` for the platform's own) |
| **Step** | Single step within a workflow with instructions |
| **SubStep** | Unit of work within a step |
| **WorkflowRun** | Specific workflow execution, always project-scoped |
| **StepRun** | Single step execution (= one terminal session) |
| **SubStepRun** | Tracked execution of one sub-step |
| **WorkflowRunAsset** | Intermediate file shared between steps |
| **Asset** | Project-level versioned file/document |

## Scope Decision

> **2026-02-22**

Workflow uses polymorphic `scope` (`Project` | `System`): a workflow belongs to one
project, and `System` holds the platform's own. `visible_for_project(project)` returns that
project's workflows (drafts left out); nothing is shared between projects, and
`duplicate_workflow` copies a workflow into another project. `WorkflowRun` always
`belongs_to :project` — execution is project-scoped.

## Implementation Phases & Dependency Graph

| Phase | Scope |
|-------|-------|
| 0 | Secrets Management |
| 1 | Agents (CRUD, selection) |
| 2 | Tools (Docker execution) |
| 3 | MCP Servers |
| 4 | Unified Container Execution |
| 4+ | Session Context (per-CLI config) |
| 4++ | Agent Sessions Core |
| 5-6 | Workflows + Artifacts |
| 7 | Billing & Integrations |

```
WORKFLOWS → SESSION CONTEXT → MCP SERVERS → TOOLS → AGENTS → SECRETS
```

---

## 1. Core Concepts

### 1.1 Entity Hierarchy

```
Workflow                          — Process definition (e.g., "Product Planning")
  └── Step                        — One agent session, one deliverable (e.g., "Create Architecture")
        └── SubStep               — Unit of work within a step (e.g., "Core Decisions")

WorkflowRun                       — Specific execution of a workflow
  └── StepRun                     — Execution of one step (= one terminal session)
        └── SubStepRun            — Tracked execution of one sub-step

WorkflowRunAsset                  — Intermediate file shared between steps
Asset                             — Project-level file with versioning, folders, tags, public sharing
```

### 1.2 Granularity Rationale

| Aixle | = BMAD equivalent | Why |
|-------|-------------------|-----|
| **Workflow** | Entire phase or business process | Full process: planning, code report, story implementation |
| **Step** | One BMAD workflow (Create Architecture, Create PRD) | 1 terminal session, 1 agent, 1 major deliverable |
| **SubStep** | One BMAD step file (step-04-decisions.md) | Trackable unit of work within a session |

A BMAD workflow like "Create Architecture" (8 step-files producing 1 document) becomes a **single Step** in Aixle with 6-8 SubSteps. No need to spin up separate containers for each section of one document.

### 1.3 Key Decisions

- **Assets, not Artifacts** — "Asset" is broader: covers uploads, agent outputs, templates, reports (repositories are their own model, see [§11](#11-github-integration))
- **Two-tier asset model** — WorkflowRunAsset (intermediate) → Asset (project-level, explicit export)
- **SubSteps as goals** — Checklist of work units, not interactive menu items
- **Mixed execution mode** — Non-interactive steps auto-proceed, interactive steps wait for user
- **Menus through instructions** — No separate menu model; step/sub-step instructions describe interactive behavior
- **Agents separate from Workflows** — Agent is LLM configuration, not a workflow entry point
- **Standalone sessions** — User can work with an agent without a workflow
- **Tri-modal → separate workflows** — PRD Create vs Validate/Edit = different workflows, not modes

---

## 2. Data Model

### 2.1 Workflow

```ruby
class Workflow < ApplicationRecord
  belongs_to :scope, polymorphic: true, optional: true  # Project | System
  belongs_to :published_by, class_name: 'User', optional: true
  has_many :steps, dependent: :destroy
  has_many :runs, class_name: 'WorkflowRun', dependent: :destroy

  # name: string
  # description: text
  has_many :base_resource_links, class_name: 'WorkflowResourceLink'
  # base_tool_ids / base_skill_ids / base_mcp_server_ids / base_asset_ids /
  #   base_repository_ids / base_config_item_ids / base_aws_oidc_role_ids / base_integration_ids: read and written as id lists,
  #   stored as WorkflowResourceLink rows (one resource per row, with a position)
  # config: jsonb (inherit_all_project_resources; the builder and API send the
  #   base_* lists inside it, and Workflow#config= moves them to the links)
  # published_at: datetime (nil until published)
  # deleted_at: datetime (soft delete)
end
```

Workflows are **scoped polymorphically** (`Project` | `System`): a workflow belongs to
one project, or to the platform (`System`). A project sees only its own workflows, through
the `visible_for_project` scope.

### 2.2 Step

One step = one terminal session = one agent = one significant deliverable.

```ruby
class Step < ApplicationRecord
  belongs_to :workflow
  belongs_to :agent, optional: true  # recommended agent for this step
  has_many :sub_steps, dependent: :destroy

  # position: integer
  # name: string ("Create Architecture")
  # instructions: text (detailed instructions for the agent — entire session)
  #
  # allow_non_interactive: boolean (default: false)
  # skip_policy: enum (never, if_outputs_exist, manual)
  #   never           — always execute
  #   if_outputs_exist — skip if all required output assets already exist
  #   manual          — ask user before step start
  #
  # input_asset_specs: jsonb
  #   [{ name: "prd", asset_type: "document", required: true },
  #    { name: "notes/*.md", required: false }]
  #   Checked before the step starts against attached assets and the outputs of every
  #   step it runs after (transitively). Names and matching: DataFlow::AssetSpec
  #   (docs/design/at-references.md §5).
  #
  # output_asset_specs: jsonb
  #   [{ name: "architecture.md", asset_type: "document", required: true },
  #    { name: "reports/*.md", required: false }]   # a glob in `name`; `name_pattern` is a legacy regex
  #   Used for validation on step completion and for skip_policy: if_outputs_exist
  #
  # depends_on_step_ids: jsonb (DAG — ids of sibling steps this step depends on)
  # preferred_model: string (optional model override, e.g. "claude-sonnet-4")
  # required_agent_runtime: string (optional — one of Step::SUPPORTED_AGENT_RUNTIMES)
  # bmad_enabled: boolean (default: false — inject BMAD-method context)
  # tool_ids / mcp_server_ids / skill_ids / asset_ids / config_item_ids / aws_oidc_role_ids / integration_ids: id lists stored as
  #   StepResourceLink rows (has_many :resource_links; one resource per row, with a position)
  # repository_ids: the same, repositories cloned for this step, merged with the workflow's base_repository_ids
  # deleted_at: datetime (soft delete — steps with runs are soft-deleted, not destroyed)
  #
  # on_failure: enum (retry, skip, fail)
  # max_retries: integer (default: 0)
end
```

Steps form a **DAG** via `depends_on_step_ids` (validated against sibling steps,
no self-reference); `root?` steps have no dependencies.

### 2.3 SubStep

Unit of work within a step. Configured in UI. Belongs to Step, not Workflow.

```ruby
class SubStep < ApplicationRecord
  belongs_to :step

  # position: integer
  # name: string ("Core Architectural Decisions") — short checklist label
  # instructions: text (optional — what the agent must do in this sub-step)
  # required: boolean (default: true)
end
```

SubSteps are NOT interactive menu items. They are a trackable checklist of work units:
- In **interactive** mode: agent works through sub-steps, user sees progress, can guide
- In **non-interactive** mode: agent processes all sub-steps autonomously

If different behavior is needed between modes, it's described in the step's `instructions`:

```markdown
## Instructions

### Interactive mode
After completing each sub-step, present options:
- [C] Continue to next sub-step
- [R] Revise current section
- [D] Deep dive — explore this topic further
- [S] Skip to next sub-step

### Non-interactive mode
Complete all sub-steps sequentially using default assumptions.
```

### 2.4 WorkflowRun

```ruby
class WorkflowRun < ApplicationRecord
  belongs_to :workflow
  belongs_to :project
  belongs_to :user
  has_many :step_runs, dependent: :destroy
  has_many :workflow_run_assets, dependent: :destroy

  # state: managed by AASM state machine (WorkflowRunStateMachine)
  #   pending → running → (paused ↔ running) → completed / failed / cancelled
  # mode: enum (interactive, non_interactive, mixed)
  #   interactive      — all steps wait for user input/approval
  #   non_interactive  — all steps auto-proceed (only if can_run_non_interactive?)
  #   mixed            — steps with allow_non_interactive auto-proceed, others wait
  #
  # input_asset_ids: jsonb (project Assets selected by user at workflow start)
  # shared_context: jsonb (accumulated from step notes, injected into CLI context files)
  # started_at: datetime
  # completed_at: datetime

  def can_run_non_interactive?
    workflow.steps.not_deleted.all?(&:allow_non_interactive)
  end
end
```

**Mode logic:**

```ruby
if workflow_run.mode == 'interactive'
  # Always wait for user action (Approve / Retry / Stop)
elsif workflow_run.mode == 'non_interactive'
  # Only possible if workflow_run.can_run_non_interactive?
  # Auto-proceed to next step
elsif workflow_run.mode == 'mixed'
  if step.allow_non_interactive
    # Auto-proceed
  else
    # Wait for user action
  end
end
```

### 2.5 StepRun

```ruby
class StepRun < ApplicationRecord
  belongs_to :workflow_run
  belongs_to :step
  belongs_to :terminal_session, optional: true
  has_many :sub_step_runs, dependent: :destroy
  has_many :produced_workflow_run_assets, class_name: 'WorkflowRunAsset',
           foreign_key: :produced_by_step_run_id

  # state: enumerize (pending, running, waiting_input, suspended, completed, failed, skipped, cancelled)
  # step_note: text (final note carried into subsequent steps' context;
  #                  populated from finish_session / fail_session notes)
  # skip_reason: string (why skipped, if state=skipped)
  # started_at: datetime
  # completed_at: datetime
  # error_message: text
end
```

### 2.6 SubStepRun

Created automatically when StepRun starts. Agent updates state via `mark_sub_step` tool.

```ruby
class SubStepRun < ApplicationRecord
  belongs_to :step_run
  belongs_to :sub_step

  # state: enumerize (pending, in_progress, completed, skipped)
  # note: text (agent writes what was done, decisions made)
  # data: jsonb (structured data — decisions, metrics, key findings)
  # started_at: datetime
  # completed_at: datetime
end
```

**Lifecycle:**

```ruby
# When StepRun is created — system auto-creates all SubStepRuns:
step.sub_steps.ordered.each do |sub_step|
  step_run.sub_step_runs.create!(
    sub_step: sub_step,
    state: :pending
  )
end

# Agent marks progress via tool:
# mark_sub_step(1, "completed", "Selected PostgreSQL 16", { db: "postgres", version: "16" })
```

**SubStepRun.data examples:**

```ruby
# SubStep: "Data Architecture Decisions"
{ decisions: [
    { category: "database", choice: "PostgreSQL 16", rationale: "..." },
    { category: "cache", choice: "Redis", rationale: "..." }
] }

# SubStep: "Security Analysis"
{ findings: { critical: 3, medium: 12, low: 28 },
  top_issues: ["SQL injection in /api/users", "Missing CSRF tokens"] }

# SubStep: "User Requirements"
{ fr_count: 12, categories: ["auth", "projects", "billing"] }
```

Data from previous SubStepRuns appears in workflow context for subsequent steps.

### 2.7 WorkflowRunAsset

Intermediate files shared between steps within a single workflow run.

```ruby
class WorkflowRunAsset < ApplicationRecord
  include WorkflowRunAssetUploader::Attachment(:file)  # Shrine attachment

  belongs_to :workflow_run
  belongs_to :produced_by_step_run, class_name: 'StepRun', optional: true

  include PubliclyShareable  # public_token, shared_at, shared_by, shared_in_session

  # name: string (relative path under /workspace/assets, see SafeRelativePath)
  # file_data: jsonb (Shrine attachment metadata)
  # content_type: string, file_size: integer, s3_key: string (written at collection)
end
```

The blob is a Shrine `file` attachment (`WorkflowRunAssetUploader`). Output collection
also writes `content_type`, `file_size` and `s3_key` as columns; `OutputValidator`
reads `file_size` and `content_type`.

**Lifecycle:**
1. Step completes → files from `/workspace/outputs/` uploaded as Shrine attachments → WorkflowRunAsset records created
2. Next step starts → the WorkflowRunAssets of every step it runs after, plus the run's picked project Assets, copied into `/workspace/assets/`
3. After workflow completes → user sees all WorkflowRunAssets and can export selected ones to project-level Assets (via the export UI / `AssetExportService`)

### 2.8 Asset (Polymorphic Scope + Separate Versions)

> **Updated 2026-02-18:** Redesigned from `belongs_to :project` to polymorphic `scope` (Company | Project). Versioning moved to separate `AssetVersion` model. `step_run_id` for workflow provenance.

```ruby
class Asset < ApplicationRecord
  belongs_to :scope, polymorphic: true          # Company | Project
  belongs_to :created_by, class_name: 'User'
  belongs_to :step_run, optional: true          # provenance: created during workflow step
  has_many :versions, class_name: 'AssetVersion', dependent: :destroy

  # name: string
  # folder: string (optional path, nested with "/" — "architecture", "specs/api"; Folder::PATH_FORMAT)
  # tags: string[] (postgres array — ["prd", "v2", "approved", "client-facing"])
  # public: boolean (default: false)
  # public_token: string (unique, generated when public=true)

  scope :for_company, ->(company) { where(scope_type: 'Company', scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: 'Project', scope_id: project.id) }

  def self.visible_for_project(project)
    where(scope_type: 'Project', scope_id: project.id)
      .or(where(scope_type: 'Company', scope_id: project.company_id))
  end
end

class AssetVersion < ApplicationRecord
  extend Enumerize
  include AssetFileUploader::Attachment(:file)  # Shrine attachment

  belongs_to :asset, inverse_of: :versions
  belongs_to :uploaded_by, class_name: 'User'

  enumerize :source, in: %i[upload workflow github session slack teams], default: :upload

  before_validation :set_version, on: :create  # auto-increment within asset

  # version: integer (auto-increment within asset)
  # file_data: text (Shrine attachment metadata)
  # content_type: string (mime type)
  # file_size: integer
  # source: enum (upload | workflow | github | session | slack | teams)
end
```

**Versioning:** Same name upload to same scope → new AssetVersion on existing Asset (auto-increment). Different name → new Asset. Metadata (name, folder, tags, public) lives on Asset, not duplicated per version.

### 2.9 Relationships with Existing Models

```ruby
class Project < ApplicationRecord
  belongs_to :company
  has_many :workflows, as: :scope      # polymorphic scope, not a direct FK
  has_many :assets, as: :scope         # same polymorphic pattern
  has_many :workflow_runs
  has_many :terminal_sessions, dependent: :nullify
end

class TerminalSession < ApplicationRecord
  belongs_to :project
  has_one :step_run
end
```

Both `Workflow` and `Asset` `belong_to :scope, polymorphic: true`. A workflow's scope is
its project (or `System`); `Company` reaches workflows only through its projects
(`has_many :workflows, through: :projects`). An asset's scope can be its project or the
company, and a company asset is visible in every project of that company.

---

## 3. Workspace Structure

### 3.1 Container Directories

```
/workspace/
├── assets/                 # READ-ONLY by instruction — files provided for this step
│   ├── prd.md              # Project Asset attached to the workflow or step, or picked for the run
│   ├── code_report.md      # WorkflowRunAsset from an earlier step
│   └── analysis.md         # WorkflowRunAsset from an earlier step
│
├── repo/                   # Repositories, one directory each (RepositoryWorkspacePath)
│   └── backend/
│
└── outputs/                # COLLECT — everything the agent produces
    ├── architecture.md     # Will become a WorkflowRunAsset
    └── diagrams/           # Will become WorkflowRunAssets
```

`Asset::CONTAINER_DIR` and `Asset::OUTPUT_DIR` name the two file directories. No index
file is written into the workspace; the instructions file lists what is there instead
(`ContextBuilders::Workspace`, and `ContextBuilders::WorkflowContext`'s "Files from
earlier steps" section, which names each file and the step that wrote it).

### 3.2 Output Collection

When step completes:
1. Collect all files from `/workspace/outputs/`
2. Upload each to S3
3. Create `WorkflowRunAsset` records (belonging to WorkflowRun, linked to StepRun)
4. Copied into `/workspace/assets/` of every later step that runs after it

---

## 4. Execution Flow

### 4.1 Start Workflow

```
User clicks "Run Workflow"
    │
    ├─→ Select mode:
    │     • Interactive (all steps require user interaction)
    │     • Non-interactive (only if WorkflowRun#can_run_non_interactive?)
    │     • Mixed (non-interactive steps auto-proceed, others wait)
    │
    ├─→ Select project Assets as inputs
    │     • Show all project Assets
    │     • Check input_asset_specs from steps — highlight recommended
    │     • User picks what to include
    │
    ▼
Create WorkflowRun (state: pending, input_asset_ids: [...])
    │
    ▼
Run the steps in passes: each pass starts, in parallel, every step whose
depends_on_step_ids are all done (the first pass: the root steps), and waits
for all of them before the next pass
```

### 4.2 Start Step

```
Start Step
    │
    ▼
Check skip_policy:
    ├─→ if_outputs_exist: check output_asset_specs → skip or execute
    ├─→ manual: show UI "Skip? [Skip / Execute]"
    ├─→ never: always execute
    │
    ▼
Create StepRun (state: pending)
Auto-create SubStepRuns from Step.sub_steps (all state: pending)
    │
    ▼
Prepare workspace:
    - Check the step's @ references and required inputs (DataFlow::Check)
    - Mount attached and run-picked Assets to /workspace/assets/<folder>/<name>
    - Copy WorkflowRunAssets of every step it runs after (transitively, nearest wins)
      to /workspace/assets/<name>
    │
    ▼
Inject workflow context into CLI context file (AGENTS.md / CLAUDE.md / .cursorrules)
    │
    ▼
Start terminal session (TerminalSession, session_type: workflow_step)
    │
    ▼
StepRun state → running
```

### 4.3 Complete Step

```
Agent completes work / User stops session
    │
    ▼
Collect files from /workspace/outputs/
Create WorkflowRunAsset records
    │
    ▼
Validate against output_asset_specs (if defined):
    ├─→ Valid: StepRun state → completed, proceed to next step
    ├─→ Invalid + retry: new StepRun, retry (up to max_retries)
    ├─→ Invalid + skip: StepRun → skipped, proceed
    └─→ Invalid + fail: StepRun → failed, WorkflowRun → failed
```

### 4.4 Complete Workflow

```
All steps completed/skipped
    │
    ▼
WorkflowRun state → completed
    │
    ▼
Show post-workflow UI:
    ┌─────────────────────────────────────────────────────────┐
    │ Workflow Run Complete: Product Planning                    │
    ├─────────────────────────────────────────────────────────┤
    │ Workflow Run Assets:                                      │
    │   📄 product-brief.md (Step 2)    [Export to Project]     │
    │   📄 PRD.md (Step 3)              [Export to Project]     │
    │   📄 architecture.md (Step 5)     [Export to Project]     │
    │   📄 epics.md (Step 6)            [Export to Project]     │
    │   📄 readiness-report.md (Step 7) ✅ Exported (public)    │
    │                                                           │
    │ [Export Selected] [Export All] [Close]                    │
    └─────────────────────────────────────────────────────────┘
```

---

## 5. Workflow Context Injection

### 5.1 Approach

Workflow context is injected directly into CLI context files (AGENTS.md, CLAUDE.md, .cursorrules, GEMINI.md) as a CRITICAL section. No separate tools for reading context — agent sees it on session start.

### 5.2 Context Template

```markdown
# ===== CRITICAL: WORKFLOW CONTEXT =====

## Workflow: Product Planning (Greenfield)

## Current Step: Create Architecture (Step 5 of 7)
Agent: Architect
Description: Make critical architectural decisions through collaborative discovery

### Sub-Steps:
1. ✅ Context Analysis
   → "Loaded PRD, identified 12 FRs and 8 NFRs"
2. ✅ Starter Template
   → "Selected Rails + React monorepo"
   → data: {framework: "Rails 7.2", frontend: "React 18"}
3. 🔄 Core Decisions — in progress
4. ⬜ Implementation Patterns
5. ⬜ Project Structure
6. ⬜ Validation

### Previous Steps:
- Step 1: Brainstorming ⏭️ Skipped
- Step 2: Product Brief ✅ "Defined B2B SaaS for dev teams"
- Step 3: Create PRD ✅
  - "Functional Requirements": data: {fr_count: 12, categories: ["auth", "projects"]}
  - "Non-Functional Requirements": data: {nfr_count: 8}
  - Note: "12 FRs, 8 NFRs, 3 risk areas identified"
- Step 4: UX Design ⏭️ Skipped

### Files from earlier steps (in /workspace/assets/):
- `/workspace/assets/product-brief.md` — written by Product Brief
- `/workspace/assets/PRD.md` — written by Create PRD

### Workflow Tools (MCP):
- list_sub_steps — list current sub-steps with statuses
- mark_sub_step(id, status, note, data) — update sub-step progress

### Workspace Rules:
- Read from: /workspace/assets/
- Save all results to: /workspace/outputs/
- Files in /workspace/assets/ are read-only — copy to outputs before editing

# ===== END WORKFLOW CONTEXT =====
```

### 5.3 Context Builder

Implemented as `ContextBuilders::WorkflowContext`
(`app/services/context_builders/workflow_context.rb`), one of a family of composable
`ContextBuilders::Base` builders (agent role, tools, workspace, board, BMAD, …). The
sketch below shows the shape; the live builder splits it into per-section methods.

```ruby
class ContextBuilders::WorkflowContext < ContextBuilders::Base
  def build(step_run)
    workflow_run = step_run.workflow_run
    workflow = workflow_run.workflow
    step = step_run.step

    previous_step_runs = workflow_run.step_runs
      .where.not(id: step_run.id)
      .where(state: [:completed, :skipped])
      .includes(step: :sub_steps, sub_step_runs: :sub_step)
      .order(:created_at)

    context = []
    context << "# ===== CRITICAL: WORKFLOW CONTEXT ====="
    context << ""
    context << "## Workflow: #{workflow.name}"
    context << "#{workflow.description}" if workflow.description.present?
    context << ""
    context << "## Current Step: #{step.name} (Step #{step.position} of #{workflow.steps.count})"
    context << "Agent: #{step.agent&.title || 'Not specified'}"
    context << ""

    # Sub-steps
    if step_run.sub_step_runs.any?
      context << "### Sub-Steps:"
      step_run.sub_step_runs.includes(:sub_step).order('sub_steps.position').each do |ssr|
        icon = case ssr.state
               when 'completed' then '✅'
               when 'in_progress' then '🔄'
               when 'skipped' then '⏭️'
               else '⬜'
               end
        line = "#{ssr.sub_step.position}. #{icon} #{ssr.sub_step.name}"
        line += " — #{ssr.state}" if ssr.in_progress?
        context << line
        context << "   → #{ssr.note.truncate(200)}" if ssr.note.present?
        if ssr.data.present?
          context << "   → data: #{ssr.data.to_json.truncate(300)}"
        end
      end
      context << ""
    end

    # Previous steps
    if previous_step_runs.any?
      context << "### Previous Steps:"
      previous_step_runs.each do |prev|
        status_icon = prev.completed? ? '✅' : '⏭️ Skipped'
        context << "- Step #{prev.step.position}: #{prev.step.name} #{status_icon}"
        # Include sub-step data from previous steps
        prev.sub_step_runs.where(state: :completed).each do |ssr|
          if ssr.data.present? || ssr.note.present?
            parts = ["  - \"#{ssr.sub_step.name}\""]
            parts << "data: #{ssr.data.to_json.truncate(200)}" if ssr.data.present?
            context << parts.join(': ')
          end
        end
        context << "  - Note: \"#{prev.step_note}\"" if prev.step_note.present?
      end
      context << ""
    end

    context << tool_descriptions
    context << workspace_rules
    context << "# ===== END WORKFLOW CONTEXT ====="

    context.join("\n")
  end
end
```

---

## 6. Internal Tools (Workflow-specific)

Internal tools are code-defined (`app/services/internal_tools/`, subclasses of
`InternalTools::Base`). Only the plumbing tools below are served without an
attachment, through an `inject_when` rule; every other tool (board, chat, Coder,
Azure DevOps, tracker, `share_asset`, `promote_asset`) must be attached to the
workflow or the step ([design](../design/tool-attachment.md)). The ones relevant
to workflow execution:

- **list_sub_steps** / **mark_sub_step** — served to every session;
  the two sub-step tracking tools (below).
- **finish_session** / **fail_session** — served to every session, interactive too;
  signal completion/failure and terminate the session. Their optional `note` is
  saved to `StepRun.step_note` when running inside a workflow.
  A session ends only through these (or a watchdog), so an agent that ends its
  turn without calling one is handled by the sweeps below (task #208).
- **read_tool_result** — injected when container tools are present; fetches status
  and presigned download URLs for an async tool execution.

- **promote_asset** — attached like any tool; promotes a file in
  `/workspace/outputs/` or an output an earlier step of the run produced to a
  versioned project-level Asset (into a folder, `/` nesting), through
  `AssetExportService`, the same service the post-workflow export UI uses.
- **share_asset** — attached like any tool; publishes a file at a
  public link (see [§8](#8-asset-public-sharing)).

There is **no** `write_step_note` internal tool. Step notes are written through
`finish_session` / `fail_session`.

### Session monitoring: one snapshot per session per pass

Several checks watch a live workflow step's terminal. They do not read it
themselves: one mechanism, `Sessions::Monitor`, reads each session once per
pass and hands the snapshot to them (task #211).

- **The pass.** `session_monitor_workflow` runs
  `Activities::Workflow::MonitorSessionsActivity` on the schedule's cron
  (`app/temporal/schedules.yml`), every minute for now, with `overlap: skip`.
  A pass is one sweep over the live workflow steps (`running` or `ready`, with
  a container). A pass that runs longer than a minute drops the next one, so the
  time between reads grows; every pass logs
  `[Sessions::Monitor] pass read=<sessions read> duration_ms=<ms> …`, which
  makes that visible. For each session the pass:
  1. asks every check whether it applies (`applies_to?`). A session no check
     applies to is not read at all;
  2. collects the snapshot parts the applicable checks need;
  3. reads the union of those parts with **one** exec, through
     `ContainerRuntime.for_session` (one runner op on a runner session, capped
     at `Settings.runners.scan_op_timeout`);
  4. hands the snapshot to the applicable checks in order, until one stops;
  5. writes what the checks keep between passes in one update.
  A session whose container is gone (`ContainerUnreachableError`) is skipped
  and left to the dead-container watchdog.
- **The parts registry** (`Sessions::Snapshot::Parts::REGISTRY`). Each part is
  one shell fragment in the read's script, delimited by a header and a footer
  with the fragment's exit status and a per-read random marker
  (`Sessions::Snapshot::Command`), so a part that fails leaves the others
  readable and the agent's own output cannot forge a delimiter.

  | Part | Fragment | What a check takes from it |
  |---|---|---|
  | `scrollback` | `tmux capture-pane -t agent -p -S -1000` | the pane; the current screen, its last 40 nonblank lines, right-trimmed (`Snapshot#screen`, `#screen_digest`, through `Sessions::ScreenDigest`) |
  | `log_mtime` | `stat -c %Y /tmp/terminal_output.log` | when the pane last sent a byte (`Snapshot#last_output_at`, `#quiet_for?`), counted only from a read that also captured the pane |
  | `clients` | `date +%s && tmux list-clients -t agent -F '#{client_readonly} #{client_activity}'` | whether a writable client typed recently, on the container's clock (`Clients#input_within?`) |
  | `agent_exit` | `tmux display-message -p -t agent '#{pane_dead}:#{pane_dead_status}:#{pane_dead_signal}'`, then, for a dead pane only, `tmux capture-pane -t agent -p -J -S -200` | whether the pane's process (an automatic session's CLI) has exited, its status or the signal that killed it, and its last lines joined (`AgentExit#dead?`, `#status`, `#signal`, `#output`) |

  The snapshot's source is replaceable per runtime (`Snapshot.source_for`).
  Today it is always an exec (`Sessions::Snapshot::ExecSource`); with task 8c a
  runner session's snapshot comes from the live log its runner pushes.
- **The interface** (`Sessions::Checks::Base`). A check implements
  `.applies_to?(session)`, `.parts`, `.kept_keys` and `#call(snapshot)`, which
  returns a `Sessions::Checks::Result`: an outcome (`:failed`, `:paused`,
  `:resumed`, `:nudged`, `:pending`, `:taken_over`, or none) and whether
  processing of this session stops there, because the check took the session
  over or found another path had. The existing `*Detector` classes stay as the
  text parsers the checks use. A check reads nothing itself; it acts itself.
- **The checks, in order.**

  | Check | Applies to | Parts | Action |
  |---|---|---|---|
  | `Checks::QuotaError` | live steps older than a minute | `scrollback`, `log_mtime` | fails the session on its recorded error, or on its own provider's quota message on the current screen once the pane has been quiet for a minute (`QuotaErrorDetector`) |
  | `Checks::BlockingPrompt` | the same, `non_interactive` only | `scrollback` | fails the session on a dialog it cannot answer (`InteractivePromptDetector`) |
  | `Checks::AgentExited` | the same, `ready` only | `agent_exit` | fails the session once its agent CLI, the pane's own process, has exited, with its status and what it printed (below) |
  | `Checks::AuthPause` | the same as `QuotaError` | `scrollback`, `log_mtime` | pauses, heals, unpauses or expires a refused login (`Sessions::AuthPause`) |
  | `Checks::TurnEnd` | `ready`, `non_interactive`, not auth-paused | `scrollback`, `clients` | types a reminder after a turn end, fails after the last one (below) |
  | `Checks::NoOutput` | `ready` steps that are not interactive and not auth-paused, from their start | `scrollback`, `log_mtime` | fails a session whose screen (Kiro) or log (other runtimes) has not changed for 30 minutes (below) |

- **The re-check before acting, and the conditional state change.** The
  snapshot and the row it came with can be seconds old. Every state change a
  check makes is a compare-and-set that reads the row again under its lock and
  checks that the session is still in the state the pass read, that the check
  still applies (state, mode, auth pause) and that the check's own condition
  still holds, then changes it in the same transaction:
  - failing goes through `Sessions::Lifecycle.fail_if` (and, for an
    admitted session, `SessionAdmissionService.fail_if!` under the writer lock),
    which reports whether it applied. Only the Temporal signal that wakes the
    container workflow is sent after the commit. The message is passed through
    `Sessions::SecretRedactor.for_session` first (`Checks::Base#fail_session`),
    and `Checks::NoOutput` redacts the whole screen before `AuthErrorDetector`
    reads it, as `Sessions::LiveLogReader` did;
  - `Sessions::AuthPause#pause!`, `#unpause_quietly` and `#expire!` do the same.
    A pause or an unpause is one transaction that locks the workflow run, then
    the session, and changes the marker and the run's state together, so a
    delivery between the two cannot leave a paused run with no paused session,
    and two sessions of one run unpaused at once resume it. A delivery's
    `resume!` types its prompt before that compare-and-set, never inside a
    transaction, and returns whether the unpause applied. `heal!` counts its
    attempt under the session's row lock, from the counter read there.
    `#unpause_quietly` and `#expire!` act only on the pause episode the pass
    observed: under the lock the row's `auth_paused_at` must be exactly the
    value the pass read, and `#expire!` computes the expiry from the locked row,
    so a fresh pause that replaced the observed one between the read and the
    action is left alone. `#pause!` redacts the banner
    (`Sessions::SecretRedactor.for_session`) before it stores it as
    `auth_pause_reason`, which the session's metadata serves and the expiry
    message quotes;
  - a reminder is counted under the lock before it is typed, and the failure
    after the last one requires the confirmation the pass acted on: the locked
    row's `turn_end_screen` and `turn_end_seen_at` must be the ones it confirmed.
  If the change did not apply, another path (`finish_session`, an auth pause, a
  delivery) has taken the session over, and the check stops with `:taken_over`.
  Every action is safe under a Temporal retry of the pass.
- **Kept state.** The snapshot is thrown away after the pass. What a check's
  later passes need lives in `terminal_sessions.metadata`, under keys that
  check owns (`Sessions::Checks::KeptState`, which refuses another check's
  key), and the pass writes all of a session's changes in one update:

  | Check | Kept between passes | Written by its action, under the row lock |
  |---|---|---|
  | `QuotaError` | nothing | — |
  | `BlockingPrompt` | nothing | — |
  | `AgentExited` | nothing | — |
  | `AuthPause` | nothing | `auth_paused_at`, `auth_pause_reason`, `auth_renewed_at`, `auth_heal_attempts`, `auth_heal_attempted_at` (also written by a delivery's `resume!` and by a refused login the CLI writes back) |
  | `TurnEnd` | `turn_end_screen`, `turn_end_seen_at` (the turn end seen on an earlier pass) | `turn_end_nudges` (the reminder count) |
  | `NoOutput` | `screen_digest`, `screen_changed_at` (the screen and when it last changed; screen-rule runtimes only) | — |

- **The on-demand snapshot.** `Sessions::Monitor.snapshot(session, parts:)`
  reads one session right now, through the same read path and registry. The
  token-refresh sweep uses it (`RefreshExpiringTokensActivity#parked?`): right
  before it rotates a grant, it reads every holder of that credential and runs
  `Checks::NoOutput#silent_for?(snapshot, 10.minutes)` on it. A pass's kept
  record cannot answer that: a grant is rotated only while every holder is
  parked, which a pass reading one session after another cannot see at one
  moment, and the record is up to a minute old, so an agent that started a turn
  since would read as parked and have its grant rotated mid-turn (the
  2026-09-05 incident). The on-demand read feeds the same kept record, and
  costs execs only for the holders of a due credential, every 5 minutes.
- **Outside the mechanism.** `ScanDeadContainersActivity` reads the pod status
  through the runtime API, with no exec; `CleanupStaleActivity` reads only
  timestamps. The live terminal in the UI, `get_session_log` and the
  `session_log` tool (`Sessions::LogTail`, `Sessions::LiveLogReader`) are reads
  for people and agents, and the launch-time wait for the shell prompt
  (`AgentBaseStrategy`) is part of starting the CLI.

### When an automatic session's agent stops without `finish_session`

Automatic sessions run each CLI's TUI. When a turn ends, the TUI waits at its
prompt for a person, whether the model forgot `finish_session` or a provider
error ended the turn. Two sweeps cover that state:

- **The reminder (Kiro, Copilot CLI, Antigravity CLI).** `Sessions::Monitor` reads each session's
  pane once a minute. When `TurnEndDetector` sees the runtime's idle prompt on two
  reads of the same screen — Kiro's under a `▸ Credits: turn …` summary, Copilot's
  `← open sidebar · Interactive` hint four lines under its `Session: … AIC used`
  line, Antigravity's `? for shortcuts` footer with an empty input box two lines
  above it — `Sessions::Checks::TurnEnd` types a reminder into the pane: call
  `finish_session` if the work is done, otherwise continue. The agent takes it
  as its next message. `Sessions::PaneInput` sends the text and `Enter` in one
  `tmux send-keys -l … ; run-shell "sleep 0.2" ; send-keys Enter` call, so a
  partial failure cannot leave an unsent draft; the pause is what makes Copilot
  CLI submit it (an `Enter` right behind a burst of text lands in what the CLI
  takes for a paste). `Sessions::AuthPause` types its resume prompt the same way.
  - Only `ready`, `non_interactive` workflow-step sessions are reminded. A
    session paused on an expired login (`Sessions::AuthPause`) is not.
  - Nothing is typed while a writable terminal client
    (`tmux list-clients`, `client_readonly` 0) has sent input in the last
    10 minutes. Attaching counts as input, so opening the session's terminal
    holds reminders for 10 minutes. A read-only viewer never does.
  - At most 3 reminders per session (`turn_end_nudges` in the session's
    metadata). The reminder is counted, and the confirmed screen forgotten,
    under the session's row lock before anything is typed. A Temporal retry of
    the pass, or a second pass over the same screen, then types nothing. A
    reminder whose typing failed is used up. The turn end after the third fails
    the session with a message that says the agent ended its turn without
    `finish_session` 4 times. The failure is a compare-and-set under the row
    lock: a session that started finishing, was finished or was auth-paused
    since the pass loaded it is left as it is.
  - The prompt is matched on its start (`› ask a question`), because a narrow
    pane wraps the placeholder. The signature is checked against captures at
    30x20, 80x24, 160x45 and 220x50.
- **A CLI that exited.** An automatic session's CLI is the agent pane's own process:
  `AgentSessionStrategy#launch_agent_in_tmux` writes the command and its prompt
  argument to `/tmp/.aixle-launch`, sets `remain-on-exit` on the pane and replaces its
  shell with `bash -ic 'exec bash /tmp/.aixle-launch'` (`respawn-pane -k`), so the CLI
  gets the environment a typed command would, `~/.bashrc` included, and the pane's pipe
  to `terminal_output.log` carries on. When the CLI exits, tmux keeps the pane with
  what it printed and reports `#{pane_dead}` and `#{pane_dead_status}`, or
  `#{pane_dead_signal}` instead of a status when a signal killed the pane's process; the
  `agent_exit` part reads them, and captures a dead pane joined (`capture-pane -J`) so
  a long line comes back whole. `Checks::AgentExited` fails an unattended `ready` step
  on the first pass that finds its pane dead, with the exit status (or the signal) and
  the CLI's last lines, redacted and cut to 500 characters (task #324: Cursor CLI refused
  `composer-2.5[effort=low]` with "Cannot use this model" and the step sat until a
  person cancelled the run). Nothing on the screen is read to decide it. An interactive
  session's CLI is still typed into the pane's shell, which its person can start it
  again from, and is left alone.
- **The silence watchdog.** `Sessions::Checks::NoOutput` runs on every pass of
  `Sessions::Monitor`, last, and reads every unattended `ready` step from its
  start, so a silent session is ended 30 to 31 minutes after it stopped
  changing.
  - **Kiro: judged by its screen.** The check keeps a digest of the current
    screen (`screen_digest`, `screen_changed_at`) and fails the session
    once its rendered screen has not changed for 30 minutes. The mtime of
    `/tmp/terminal_output.log` is not enough, because an idle TUI repaints its
    unchanged screen whenever the pane is resized, for example by an attached
    web terminal. A working Kiro keeps its screen changing
    (`Kiro is working · 1m 15s`).
  - **Other runtimes: judged by the log's mtime, as before.** The screen rule is
    opt-in through `Checks::NoOutput::SCREEN_RULE_RUNTIMES`, which holds
    `kiro_cli` only. A runtime joins once its working screen, tool calls
    included, has been captured on its pinned CLI and shown to change between
    reads; an indicator that animates only through colour would otherwise read
    as silence while its agent works.
  - When the pane shows Kiro's idle prompt, the failure says the agent stopped
    without `finish_session`.
  - The token-refresh sweep reads the same verdict through
    `silent_for?(snapshot, 10.minutes)`, on an on-demand snapshot (above). A
    Kiro session parked at its prompt counts as
    parked even while it repaints, and a working one does not. Other runtimes
    count as parked only when their log got no bytes for 10 minutes, as before.

Kiro's `Stop` hook was measured as an alternative on kiro-cli 3.0.0 and not
used: a `{"decision":"block"}` answer makes the agent continue, but the hook
runs only once per prompt, does not run when a provider error ends the turn,
and receives only the CLI's own `session_id`, `hook_event_name` and `cwd`.
The runtimes without a `TurnEndDetector` signature (Claude Code, Cursor CLI, Codex,
Gemini CLI, Grok) have the same gap and get only the mtime watchdog until a
signature for their idle prompt and a capture of their working screen are
measured.

### 6.1 list_sub_steps

```json
{
  "name": "list_sub_steps",
  "description": "List current step's sub-steps with their statuses",
  "parameters": {}
}
```

Returns:
```json
[
  { "id": 1, "name": "Context Analysis", "status": "completed", "note": "...", "data": {...} },
  { "id": 2, "name": "Starter Template", "status": "completed", "note": "...", "data": {...} },
  { "id": 3, "name": "Core Decisions", "status": "in_progress", "note": null, "data": null },
  { "id": 4, "name": "Implementation Patterns", "status": "pending", "note": null, "data": null }
]
```

### 6.2 mark_sub_step

```json
{
  "name": "mark_sub_step",
  "description": "Update sub-step status with optional note and structured data. SubStepRuns are pre-created when step starts — this tool updates existing records.",
  "parameters": {
    "id": { "type": "integer", "required": true },
    "status": { "type": "string", "enum": ["in_progress", "completed", "skipped"], "required": true },
    "note": { "type": "string", "required": false, "description": "What was done, decisions made" },
    "data": { "type": "object", "required": false, "description": "Structured data — decisions, metrics, findings" }
  }
}
```

---

## 7. Asset Versioning

Versioning is **not** a chain of `Asset` rows. Each `Asset` `has_many :versions`
(`AssetVersion`), and the blob lives on the version, not the asset. The `assets`
table has no `parent_id` / `version` / `s3_key` / `source_workflow_run_asset`
columns — see [§2.8](#28-asset-polymorphic-scope--separate-versions) for the models.

### 7.1 How versions are created

- **Same name into the same scope+folder** → a new `AssetVersion` on the existing
  `Asset`. `AssetVersion#set_version` (a `before_validation` on create) sets
  `version = (asset.versions.maximum(:version) || 0) + 1`.
- **Different name** → a new `Asset` (with its first version).
- Metadata (name, folder, tags, public flag, scope) lives on `Asset` and is not
  duplicated per version.

### 7.2 Version provenance

Each `AssetVersion` records where it came from via an `enumerize :source`
(`upload | workflow | github | session | slack | teams`) plus `uploaded_by`. Workflow
provenance is additionally captured on `Asset#step_run` (the step run that produced
it). Resolution helpers: `Asset#latest_version` and
`Asset#resolve_version(version_number)`.

---

## 8. Asset Public Sharing

A file can be published at a stable anonymous link, `/share/:token`, served by
`Web::PublicAssetsController` without a sign-in. Three kinds of file can be shared,
through the `PubliclyShareable` concern: a project `Asset`, a workflow run output
(`WorkflowRunAsset`) and a task attachment (`TaskAsset`). One route serves all three,
so a token is unique across the three tables, and `PubliclyShareable.find_shared`
looks it up in each.

- **`GET /share/:token`** renders the app's own viewer page, which may be embedded
  anywhere (`frame-ancestors *`) and loads the file in a sandboxed iframe.
- **`GET /share/:token/raw`** streams the file's bytes through the app, not as a
  storage redirect, under `Content-Security-Policy: sandbox` and
  `X-Content-Type-Options: nosniff`: the content is untrusted, since an agent may
  have written arbitrary HTML or JavaScript. For an `Asset` it serves the latest
  version, so the link stays the same as new versions arrive.
- **Making a link:** the `share_asset` tool, once attached to the step, is
  what shares a file: a project asset, an output of the session's run, or an
  attachment of a task on the project's board. A company asset is never shared, since
  every project of the company sees it. `share!` is idempotent (a shared file keeps its
  link) and records who shared it and from which session (`shared_by`,
  `shared_in_session`, `shared_at`). A shared file's resource carries its `share_url`.
- **Revoking:** `DELETE …/share` (the `unshare` action) on the project asset, company
  asset, run output and task attachment API routes; the UI's "Stop sharing" calls it
  for assets and task attachments. Unsharing clears the token, so the old link stays
  dead and sharing again makes a new one. Deleting an asset clears its share too.

---

## 9. Validation

### 9.1 Output Asset Specs

```yaml
output_asset_specs:
  - name: "architecture.md"     # a path under /workspace/outputs, or a glob ("reports/*.md")
    asset_type: document        # a free-text label; nothing checks it
    required: true
    min_size: 500               # bytes
    required_sections:          # heading text, matched at any heading level, case-insensitive
      - "Core Decisions"
      - "Implementation Patterns"
```

`name_pattern` (a regular expression) is the legacy alternative to `name`.
`min_size` and `required_sections` are set through the Builder's and personal MCP's
`create_workflow_step` / `update_workflow_step`; the API's step params take only
`name`, `asset_type`, `required` and `name_pattern`.

### 9.2 Validation Process

`OutputValidator` checks each spec against the step's collected outputs:

1. **Existence** — a required spec with no matching output fails
2. **Naming** — `name` matches exactly or as a glob; `name_pattern` as a regex
3. **Structure** — each matching markdown output (`.md`, or a markdown content type) has every `required_sections` heading
4. **Size** — each matching output is at least `min_size` bytes (`file_size`)

### 9.3 On Validation Failure

Per-step via `on_failure` + `max_retries`:
- `retry` — new StepRun, try again
- `skip` — mark skipped, proceed
- `fail` — stop workflow

---

## 10. BMAD Mapping

### 10.1 How BMAD Workflows Map to Aixle

| BMAD | Aixle | Notes |
|------|-------|-------|
| Phase/business process | **Workflow** | "Product Planning", "Code Report" |
| One BMAD workflow (Create Architecture) | **Step** | 1 session, 1 agent, 1 deliverable |
| BMAD step file (step-04-decisions.md) | **SubStep** | Trackable work unit |
| Tri-modal (Create/Validate/Edit) | Separate Workflows | Not modes within one workflow |
| A/P/C menu | Step instructions | Agent presents choices in interactive mode |
| Agent persona (PM, Architect, Dev) | `agent_id` on Step | Optional, recommended agent |
| Config + planning docs | Assets + workflow context | Persistent, versioned |
| sprint-status.yaml | WorkflowRun + StepRun | Automatic tracking with UI |

### 10.2 Greenfield Project Example

```
Workflow: "Product Planning (Greenfield)"
Mode: mixed

Step 1: "Brainstorming & Research"
  Agent: Analyst | interactive | skip_policy: manual
  SubSteps: Session Setup, Technique Selection, Execution, Organization
  Output: brainstorming-report.md

Step 2: "Create Product Brief"
  Agent: Analyst | interactive | skip_policy: manual
  SubSteps: Vision, Users, Metrics, Scope, Review
  Output: product-brief.md

Step 3: "Create PRD"
  Agent: PM | interactive
  SubSteps: Discovery, Vision, Users, FRs, NFRs, Risks, Metrics, Scope, Review
  Output: PRD.md

Step 4: "Create UX Design"
  Agent: UX Designer | interactive | skip_policy: manual
  SubSteps: Research, Personas, Flows, Wireframes, Specs, Review
  Output: ux-spec.md

Step 5: "Create Architecture"
  Agent: Architect | interactive
  SubSteps:
    1. Context Analysis
    2. Starter Template Selection
    3. Core Decisions (Data, Auth, API, Frontend, Infra)
    4. Implementation Patterns
    5. Project Structure
    6. Validation
  Output: architecture.md

Step 6: "Create Epics & Stories"
  Agent: PM | interactive
  SubSteps: Validate Prerequisites, Design Epics, Create Stories, Validation
  Output: epics.md + story files

Step 7: "Readiness Check"
  Agent: Architect | allow_non_interactive: true
  SubSteps: Document Discovery, PRD Analysis, Epic Coverage, UX Alignment, Assessment
  Output: readiness-report.md
```

### 10.3 Code Report Example

```
Workflow: "Code Report"
Mode: mixed

Step 1: "Generate Code Report"
  Agent: code-analyst | allow_non_interactive: true
  SubSteps:
    1. Security Analysis
    2. Code Quality Metrics
    3. Dependency Audit
    4. Architecture Review
    5. Test Coverage
    6. Performance Hotspots
    7. Documentation Completeness
    8. Recommendations
  Output: code_report.md

Step 2: "Create Client Report"
  Agent: report-designer | interactive
  SubSteps:
    1. Review sections with user
    2. Generate styled HTML
    3. Export as public asset
  Output: report.html (exported as public Asset)
```

### 10.4 What Aixle Adds Over BMAD

| BMAD limitation | Aixle solution |
|-----------------|----------------|
| Fresh chat = lost context | Assets persist, shared_context carries decisions |
| Manual agent switching | `agent_id` on Step — system provisions correct agent |
| sprint-status.yaml tracking | WorkflowRun + StepRun + SubStepRun — full history with UI |
| Everything interactive | Mixed mode — TestArch-like steps auto-proceed |
| Files overwritten | Asset versioning — full history |
| No sharing | Public assets with shareable links |
| No cost tracking | MITM proxy — cost per step |
| No structured progress | SubStepRun.data — structured findings, decisions |

---

## 11. GitHub Integration

### 11.1 Repositories

A repository is its own model, `Repository` (`repositories` table), not an asset. It
belongs to a project and to the integration it is cloned through (GitHub, GitLab,
Bitbucket or Azure DevOps), or to none for a public repository. A step names
repositories in its `repository_ids`, merged with the workflow's `base_repository_ids`.

### 11.2 Clone Process

`SessionContextService` clones each repository the session names into the container,
with a token minted from the repository's integration, or anonymously for a public
repository. `RepositoryWorkspacePath` decides the directory once, for the whole set:
`/workspace/repo/<name>`, or an id-qualified directory when two names would collide
(and for every Azure DevOps repository). The paths are stored in the session's
metadata and read back from there, so a renamed remote never moves a live checkout.

---

## 12. Open Questions — Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Naming | ✅ Asset (not Artifact) |
| 2 | Entity naming | ✅ Workflow → Step → SubStep (clean, no prefixes) |
| 3 | Granularity | ✅ BMAD workflow = Aixle Step; BMAD step-file = Aixle SubStep |
| 4 | Tool calling | ✅ MCP servers |
| 5 | Parallel steps | ✅ Steps form a DAG (`depends_on_step_ids`); each pass runs every ready step in parallel |
| 6 | Branching | ❌ Not needed |
| 7 | Execution modes | ✅ Interactive / Non-interactive / Mixed |
| 8 | Intermediate files | ✅ Two-tier: WorkflowRunAsset → explicit export to Asset |
| 9 | Sub-steps | ✅ Separate model, configurable in UI, pre-created on StepRun start |
| 10 | Agent context | ✅ Injected into CLI context files, no read tools |
| 11 | Skip policy | ✅ never / if_outputs_exist / manual (no condition) |
| 12 | Workflow scope | ✅ Polymorphic scope (Project / System); a workflow belongs to one project |
| 13 | Asset versioning | ✅ Same name → new version; different name → new asset |
| 14 | Asset organization | ✅ Nested folders (paths, `/`) + tags |
| 15 | Public sharing | ✅ public flag + public_token → shareable URL |
| 16 | Menus | ✅ Through step/sub-step instructions, not separate model |
| 17 | Tri-modal | ✅ Separate workflows (Create PRD vs Validate/Edit PRD) |
| 18 | SubStepRun creation | ✅ Auto-created when StepRun starts, agent updates via tool |
| 19 | SubStepRun data | ✅ jsonb for structured data (decisions, metrics, findings) |

---

## 13. Implementation Notes

The subsystems this design builds on all exist today: secrets management, Agents,
Tools, MCP servers, container/session execution, and session context injection. The
workflow and asset stack described above (Asset + AssetVersion, Workflow / Step /
SubStep definitions, WorkflowRun / StepRun / SubStepRun execution, WorkflowRunAsset,
the sub-step internal tools, `ContextBuilders::WorkflowContext`, and public sharing)
is implemented.

---

_Document v3 generated from design session 2026-02-13._
_Key changes from v2: Objective→SubStep, correct granularity (BMAD workflow=Step), SubStepRun auto-creation + data, BMAD mapping section._
