# Workflow & Asset Architecture Design

**Date:** 2026-02-13 (v3)
**Previous versions:** v2 2026-02-13, v1 2026-01-30
**Status:** Approved
**Author:** Artem Petrov + AI Analysis

---

## Related Documents

| Document | Description |
|----------|-------------|
| [Architecture](./architecture.md) | Core architecture decisions, tech stack |
| [PRD](./prd.md) | Product Requirements Document |
| [Implementation Notes](./implementation-notes.md) | Detailed implementation decisions |

---

## Overview

Architecture of the workflow and asset system for Palad. This document defines how workflows, steps, sub-steps, assets, and their execution are modeled and connected.

Key design principle: **Palad is a persistent BMAD runtime** — BMAD today works through fresh LLM chats with markdown files; Palad turns this into a persistent system with tracking, assets, versioning, and automation.

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

| Palad | = BMAD equivalent | Why |
|-------|-------------------|-----|
| **Workflow** | Entire phase or business process | Full process: planning, code report, story implementation |
| **Step** | One BMAD workflow (Create Architecture, Create PRD) | 1 terminal session, 1 agent, 1 major deliverable |
| **SubStep** | One BMAD step file (step-04-decisions.md) | Trackable unit of work within a session |

A BMAD workflow like "Create Architecture" (8 step-files producing 1 document) becomes a **single Step** in Palad with 6-8 SubSteps. No need to spin up separate containers for each section of one document.

### 1.3 Key Decisions

- **Assets, not Artifacts** — "Asset" is broader: covers uploads, agent outputs, repos, templates, reports
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
  belongs_to :project
  has_many :steps, dependent: :destroy
  has_many :runs, class_name: 'WorkflowRun'

  # name: string
  # description: text
  # config: jsonb (additional settings)

  def can_run_non_interactive?
    steps.all?(&:allow_non_interactive)
  end
end
```

### 2.2 Step

One step = one terminal session = one agent = one significant deliverable.

```ruby
class Step < ApplicationRecord
  belongs_to :workflow
  belongs_to :agent, optional: true  # recommended agent for this step
  has_many :sub_steps, dependent: :destroy

  # position: integer
  # name: string ("Create Architecture")
  # description: text (what the step does)
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
  #    { name: "repo", asset_type: "repository", required: false }]
  #   NOTE: actual resolution = user-selected Assets + all WorkflowRunAssets from previous steps
  #
  # output_asset_specs: jsonb
  #   [{ name: "architecture", asset_type: "document", required: true, name_pattern: "*.md" }]
  #   Used for validation on step completion and for skip_policy: if_outputs_exist
  #
  # agent_runtime: string (optional — claude_code, cursor_cli, gemini_cli, codex)
  # tool_ids: jsonb (which tools/MCP servers are available in this step)
  #
  # on_failure: enum (retry, skip, fail)
  # max_retries: integer (default: 0)
end
```

### 2.3 SubStep

Unit of work within a step. Configured in UI. Belongs to Step, not Workflow.

```ruby
class SubStep < ApplicationRecord
  belongs_to :step

  # position: integer
  # name: string ("Core Architectural Decisions")
  # description: text (what needs to be accomplished)
  # instructions: text (optional — additional context for this sub-step)
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

  # status: enum (pending, running, paused, completed, failed, cancelled)
  # mode: enum (interactive, non_interactive, mixed)
  #   interactive      — all steps wait for user input/approval
  #   non_interactive  — all steps auto-proceed (only if workflow.can_run_non_interactive?)
  #   mixed            — steps with allow_non_interactive auto-proceed, others wait
  #
  # input_asset_ids: jsonb (project Assets selected by user at workflow start)
  # shared_context: jsonb (accumulated from step notes, injected into CLI context files)
  # started_at: datetime
  # completed_at: datetime
end
```

**Mode logic:**

```ruby
if workflow_run.mode == 'interactive'
  # Always wait for user action (Approve / Retry / Stop)
elsif workflow_run.mode == 'non_interactive'
  # Only possible if workflow.can_run_non_interactive?
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

  # status: enum (pending, running, waiting_input, completed, failed, skipped)
  # step_note: text (written by agent via write_step_note tool)
  # skip_reason: string (why skipped, if status=skipped)
  # started_at: datetime
  # completed_at: datetime
  # error_message: text
end
```

### 2.6 SubStepRun

Created automatically when StepRun starts. Agent updates status via `mark_sub_step` tool.

```ruby
class SubStepRun < ApplicationRecord
  belongs_to :step_run
  belongs_to :sub_step

  # status: enum (pending, in_progress, completed, skipped)
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
    status: :pending
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
  belongs_to :workflow_run
  belongs_to :produced_by_step_run, class_name: 'StepRun', optional: true

  # name: string (filename)
  # s3_key: string
  # content_type: string (mime type)
  # file_size: integer
end
```

**Lifecycle:**
1. Step completes → all files from `/workspace/output/` uploaded to S3 → WorkflowRunAsset records created
2. Next step starts → ALL WorkflowRunAssets from previous steps + user-selected project Assets mounted to `/workspace/input/`
3. After workflow completes → user sees all WorkflowRunAssets and can export selected ones to project-level Assets
4. `export_asset` tool can also promote during workflow execution

### 2.8 Asset (Polymorphic Scope + Separate Versions)

> **Updated 2026-02-18:** Redesigned from `belongs_to :project` to polymorphic `scope` (Company | Project), matching Agent/Tool/Skill pattern. Versioning moved to separate `AssetVersion` model. `step_run_id` for workflow provenance.

```ruby
class Asset < ApplicationRecord
  belongs_to :scope, polymorphic: true          # Company | Project (same pattern as Agent/Tool/Skill)
  belongs_to :created_by, class_name: 'User'
  belongs_to :step_run, optional: true          # provenance: created during workflow step
  has_many :versions, class_name: 'AssetVersion', dependent: :destroy

  # name: string
  # asset_type: enum (document, image, archive, code, diagram, data, html, repository, other)
  # folder: string (optional, one-level nesting — "architecture", "stories", "reports")
  # tags: string[] (postgres array — ["prd", "v2", "approved", "client-facing"])
  # public: boolean (default: false)
  # public_token: string (unique, generated when public=true)

  scope :for_company, ->(company) { where(scope_type: 'Company', scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: 'Project', scope_id: project.id) }

  def self.merged_for_project(project)
    where(scope_type: 'Project', scope_id: project.id)
      .or(where(scope_type: 'Company', scope_id: project.company_id))
  end
end

class AssetVersion < ApplicationRecord
  belongs_to :asset
  belongs_to :uploaded_by, class_name: 'User'

  # version: integer (auto-increment within asset)
  # file_data: text (Shrine attachment data)
  # content_type: string (mime type)
  # file_size: integer
  # provenance: jsonb
  #   { source: "upload", user_id: X }
  #   { source: "workflow", step_run_id: Y, step_name: "..." }
  #   { source: "github", repo_url: "...", branch: "...", commit: "..." }
end
```

**Versioning:** Same name upload to same scope → new AssetVersion on existing Asset (auto-increment). Different name → new Asset. Metadata (name, folder, tags, public) lives on Asset, not duplicated per version.

### 2.9 Relationships with Existing Models

```ruby
class Project < ApplicationRecord
  has_many :workflows
  has_many :assets
  has_many :terminal_sessions
end

class TerminalSession < ApplicationRecord
  belongs_to :project
  has_one :step_run
end
```

---

## 3. Workspace Structure

### 3.1 Container Directories

```
/workspace/
├── input/                  # READONLY — all available files for this step
│   ├── _index.md           # Auto-generated: describes all input files
│   ├── prd.md              # Project Asset (selected at workflow start)
│   ├── template.md         # Project Asset (selected at workflow start)
│   ├── repo/               # GitHub clone (if repository asset)
│   ├── code_report.md      # WorkflowRunAsset from previous step
│   └── analysis.md         # WorkflowRunAsset from previous step
│
└── output/                 # COLLECT — everything agent produces
    ├── architecture.md     # Will become WorkflowRunAsset
    └── diagrams/           # Will become WorkflowRunAssets
```

### 3.2 Dynamic _index.md

Auto-generated at each step start:

```markdown
# Workspace Input Index

## Project Assets (selected at workflow start)
- **prd.md** — Product Requirements Document (document, 2.3KB)
- **company-template.md** — Code Report Template (document, 1.1KB)
- **repo/** — Repository: github.com/acme/backend (repository, branch: main)

## Workflow Run Assets (from previous steps)
- **code_report.md** — from Step 1 "Generate Code Report" (document, 15.2KB)
- **security_findings.json** — from Step 1 "Generate Code Report" (data, 3.4KB)

## Instructions
- Read from: /workspace/input/
- Save all results to: /workspace/output/
- If you need to modify an existing document, copy it from input to output first
```

### 3.3 Output Collection

When step completes:
1. Collect all files from `/workspace/output/`
2. Upload each to S3
3. Create `WorkflowRunAsset` records (belonging to WorkflowRun, linked to StepRun)
4. Available to all subsequent steps automatically

---

## 4. Execution Flow

### 4.1 Start Workflow

```
User clicks "Run Workflow"
    │
    ├─→ Select mode:
    │     • Interactive (all steps require user interaction)
    │     • Non-interactive (only if workflow.can_run_non_interactive?)
    │     • Mixed (non-interactive steps auto-proceed, others wait)
    │
    ├─→ Select project Assets as inputs
    │     • Show all project Assets
    │     • Check input_asset_specs from steps — highlight recommended
    │     • User picks what to include
    │
    ▼
Create WorkflowRun (status: pending, input_asset_ids: [...])
    │
    ▼
Start first step
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
Create StepRun (status: pending)
Auto-create SubStepRuns from Step.sub_steps (all status: pending)
    │
    ▼
Prepare workspace:
    - Mount user-selected project Assets to /workspace/input/
    - Mount ALL WorkflowRunAssets from previous steps to /workspace/input/
    - Generate /workspace/input/_index.md
    │
    ▼
Inject workflow context into CLI context file (AGENTS.md / CLAUDE.md / .cursorrules)
    │
    ▼
Start terminal session (TerminalSession, session_type: workflow_step)
    │
    ▼
StepRun status → running
```

### 4.3 Complete Step

```
Agent completes work / User stops session
    │
    ▼
Collect files from /workspace/output/
Create WorkflowRunAsset records
    │
    ▼
Validate against output_asset_specs (if defined):
    ├─→ Valid: StepRun status → completed, proceed to next step
    ├─→ Invalid + retry: new StepRun, retry (up to max_retries)
    ├─→ Invalid + skip: StepRun → skipped, proceed
    └─→ Invalid + fail: StepRun → failed, WorkflowRun → failed
```

### 4.4 Complete Workflow

```
All steps completed/skipped
    │
    ▼
WorkflowRun status → completed
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

### Available Input Files:
See /workspace/input/_index.md for full list.

### Workflow Tools:
- list_sub_steps — list current sub-steps with statuses
- mark_sub_step(id, status, note, data) — update sub-step progress
- write_step_note(note) — save a note for future steps
- export_asset(file, tags, folder, public) — promote output to project asset

### Workspace Rules:
- Read from: /workspace/input/
- Save all results to: /workspace/output/
- If you need to modify an existing document, copy from input to output first

# ===== END WORKFLOW CONTEXT =====
```

### 5.3 Context Assembler

```ruby
class WorkflowContextAssembler
  def assemble(step_run)
    workflow_run = step_run.workflow_run
    workflow = workflow_run.workflow
    step = step_run.step

    previous_step_runs = workflow_run.step_runs
      .where.not(id: step_run.id)
      .where(status: [:completed, :skipped])
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
    context << "Description: #{step.description}"
    context << ""

    # Sub-steps
    if step_run.sub_step_runs.any?
      context << "### Sub-Steps:"
      step_run.sub_step_runs.includes(:sub_step).order('sub_steps.position').each do |ssr|
        icon = case ssr.status
               when 'completed' then '✅'
               when 'in_progress' then '🔄'
               when 'skipped' then '⏭️'
               else '⬜'
               end
        line = "#{ssr.sub_step.position}. #{icon} #{ssr.sub_step.name}"
        line += " — #{ssr.status}" if ssr.in_progress?
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
        prev.sub_step_runs.where(status: :completed).each do |ssr|
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

Four internal tools, automatically available when `session_type = workflow_step`.

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

### 6.3 write_step_note

```json
{
  "name": "write_step_note",
  "description": "Save a note for this step. Visible to agents in subsequent steps via workflow context.",
  "parameters": {
    "note": { "type": "string", "required": true }
  }
}
```

Writes to `StepRun.step_note`. Appends if called multiple times.

### 6.4 export_asset

```json
{
  "name": "export_asset",
  "description": "Promote a file from /workspace/output/ to a project-level Asset. Optionally make it public with a shareable link.",
  "parameters": {
    "file": { "type": "string", "required": true, "description": "Filename in /workspace/output/" },
    "tags": { "type": "array", "items": { "type": "string" }, "required": false },
    "folder": { "type": "string", "required": false },
    "public": { "type": "boolean", "required": false, "default": false }
  }
}
```

Logic:
1. Find file in `/workspace/output/{file}`
2. Upload to S3 (or find existing WorkflowRunAsset)
3. Check if Asset with same name exists → new version or new Asset
4. If `public: true` → generate `public_token`, return shareable URL

---

## 7. Asset Versioning

### 7.1 Version Chain

```
Asset (v1, parent: nil)  ← root
    └─→ Asset (v2, parent: v1)
            └─→ Asset (v3, parent: v1)  # parent always points to root
```

### 7.2 Version Creation on Export

```ruby
def export_to_project_asset(workflow_run_asset, options = {})
  project = workflow_run_asset.workflow_run.project
  existing_root = project.assets.find_by(name: workflow_run_asset.name, parent_id: nil)

  attrs = {
    project: project,
    name: workflow_run_asset.name,
    s3_key: workflow_run_asset.s3_key,
    content_type: workflow_run_asset.content_type,
    file_size: workflow_run_asset.file_size,
    source_workflow_run_asset: workflow_run_asset,
    folder: options[:folder],
    tags: options[:tags] || [],
    public: options[:public] || false,
    public_token: options[:public] ? SecureRandom.urlsafe_base64(16) : nil,
    provenance: build_provenance(workflow_run_asset)
  }

  if existing_root
    attrs[:parent] = existing_root
    attrs[:version] = existing_root.versions.count + 2
  else
    attrs[:version] = 1
  end

  Asset.create!(attrs)
end
```

---

## 8. Asset Public Sharing

### 8.1 Shareable Endpoint

```ruby
class SharedAssetsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    asset = Asset.find_by!(public_token: params[:token], public: true)
    # For HTML: render inline; for other types: redirect to S3 pre-signed URL
  end
end
```

URL: `https://app.example.com/shared/{public_token}`

### 8.2 Management

- Toggle `public` on/off from Asset detail view
- `public_token` generated once and preserved (stable URL)
- Revoking: set `public: false` (token preserved for re-enabling)

---

## 9. Validation

### 9.1 Output Asset Specs

```yaml
output_asset_specs:
  - name: "architecture"
    asset_type: document
    name_pattern: "*.md"
    required: true
    validation:
      format: markdown
      required_sections:
        - "## Core Decisions"
        - "## Implementation Patterns"
      min_length: 500
```

### 9.2 Validation Process

1. **Existence** — file exists in output
2. **Naming** — matches name_pattern
3. **Structure** — contains required sections (markdown)
4. **Size** — minimum length

### 9.3 On Validation Failure

Per-step via `on_failure` + `max_retries`:
- `retry` — new StepRun, try again
- `skip` — mark skipped, proceed
- `fail` — stop workflow

---

## 10. BMAD Mapping

### 10.1 How BMAD Workflows Map to Palad

| BMAD | Palad | Notes |
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

### 10.4 What Palad Adds Over BMAD

| BMAD limitation | Palad solution |
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

### 11.1 Repository as Asset

Repositories are a special `asset_type`. Cloned and mounted as directories.

```ruby
# Asset with asset_type: "repository"
# provenance: { source: "github", repo_url: "...", branch: "main", commit: "abc123" }
# Mounted to: /workspace/input/repo/
```

### 11.2 Clone Process

```ruby
class WorkspacePreparator
  def prepare_repository_asset(asset, workspace_path)
    repo_path = "#{workspace_path}/input/repo"
    Git.clone(
      asset.provenance['repo_url'], repo_path,
      depth: asset.provenance['depth'] || 1,
      branch: asset.provenance['branch'] || 'main',
      credentials: resolve_github_credentials(asset.project)
    )
  end
end
```

---

## 12. Open Questions — Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Naming | ✅ Asset (not Artifact) |
| 2 | Entity naming | ✅ Workflow → Step → SubStep (clean, no prefixes) |
| 3 | Granularity | ✅ BMAD workflow = Palad Step; BMAD step-file = Palad SubStep |
| 4 | Tool calling | ✅ MCP servers |
| 5 | Parallel steps | ❌ Sequential only |
| 6 | Branching | ❌ Not needed |
| 7 | Execution modes | ✅ Interactive / Non-interactive / Mixed |
| 8 | Intermediate files | ✅ Two-tier: WorkflowRunAsset → explicit export to Asset |
| 9 | Sub-steps | ✅ Separate model, configurable in UI, pre-created on StepRun start |
| 10 | Agent context | ✅ Injected into CLI context files, no read tools |
| 11 | Skip policy | ✅ never / if_outputs_exist / manual (no condition) |
| 12 | Workflow scope | ✅ Project-level only |
| 13 | Asset versioning | ✅ Same name → new version; different name → new asset |
| 14 | Asset organization | ✅ One-level folders + tags |
| 15 | Public sharing | ✅ public flag + public_token → shareable URL |
| 16 | Menus | ✅ Through step/sub-step instructions, not separate model |
| 17 | Tri-modal | ✅ Separate workflows (Create PRD vs Validate/Edit PRD) |
| 18 | SubStepRun creation | ✅ Auto-created when StepRun starts, agent updates via tool |
| 19 | SubStepRun data | ✅ jsonb for structured data (decisions, metrics, findings) |

---

## 13. Implementation Priority

### Prerequisites (already implemented)

| # | Component | Status |
|---|-----------|--------|
| P0 | Secrets Management | ✅ Done (Epic 4) |
| P1 | Agents | ✅ Done (Epic 5) |
| P2 | Tools | ✅ Done (Epic 6) |
| P3 | MCP Servers | ✅ Done (Epic 7) |
| P4 | Container Execution | ✅ Done (Epic 8) |
| P4+ | Session Context | ✅ Done (Epic 9) |
| P4++ | Agent Sessions Core | 🔄 In Progress (Epic 10) |

### Workflow & Asset Implementation Phases

| Phase | Scope | Key Deliverables |
|-------|-------|------------------|
| **A** | Asset Foundation | Asset model, S3, upload, versioning, folders/tags |
| **B** | Asset UI + Public | List, detail, upload, public toggle, shareable links |
| **C** | Workflow Definition | Workflow, Step, SubStep models + CRUD UI |
| **D** | Workflow Execution | WorkflowRun, StepRun, SubStepRun, WorkflowRunAsset, Temporal |
| **E** | Internal Tools | 4 tools: list_sub_steps, mark_sub_step, write_step_note, export_asset |
| **F** | Context + _index.md | WorkflowContextAssembler, _index.md, CLI context injection |
| **G** | Execution Modes | Interactive/non-interactive/mixed, skip policies |
| **H** | Post-workflow UI | WorkflowRun detail, asset export selection, public links |

---

_Document v3 generated from design session 2026-02-13_
_Key changes from v2: Objective→SubStep, correct granularity (BMAD workflow=Step), SubStepRun auto-creation + data, BMAD mapping section_
