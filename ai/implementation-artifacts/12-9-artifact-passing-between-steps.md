# Story 12.9: Artifact Passing Between Steps

Status: done

## Story

As a project member,
I want workflow step outputs to automatically become inputs for subsequent steps,
so that agents build on previous work without manual file management.

## Acceptance Criteria

1. **AC1: Output collection** — When a step completes, all files from `/workspace/outputs/` are collected, uploaded to S3, and recorded as `WorkflowRunAsset` records. Each asset captures: name, s3_key, content_type, file_size, produced_by_step_run_id.

2. **AC2: Input mounting** — When a new step starts, ALL WorkflowRunAssets from previous steps in the same WorkflowRun are mounted to `/workspace/input/` in the container. Additionally, user-selected project-level Assets (from `input_asset_ids`) are mounted.

3. **AC3: Dynamic _index.md** — System auto-generates `/workspace/input/_index.md` listing all available input files, their sources (which step produced them or "user-selected"), sizes, and types. Follows the template from workflow-architecture.md section 3.2.

4. **AC4: Variable replacement** — Step instructions support `{{artifact_name}}` variables that are replaced with actual file paths at runtime. E.g., `{{prd}}` → `/workspace/input/prd.md`. Resolution: match against WorkflowRunAsset names and project Asset names.

5. **AC5: Input requirements validation** — Before step starts, check `input_asset_specs` requirements. If a required input is missing: in interactive mode, prompt user to select/upload; in non-interactive mode, log warning and proceed (let agent handle missing input).

6. **AC6: Output validation** — After step completes, check `output_asset_specs` requirements:
   - **Existence** — required files present in `/workspace/outputs/`
   - **Naming** — matches `name_pattern` if specified
   - **Structure** — contains `required_sections` for markdown files (optional check)
   - **Size** — minimum length if specified
   If validation fails, apply step's `on_failure` policy.

7. **AC7: Provenance tracking** — WorkflowRunAsset records track: which step produced them, when, from which workflow run. When exported to project-level Asset (via `export_asset` tool), provenance carries over to AssetVersion.

8. **AC8: Post-workflow asset review** — After workflow completes, show all WorkflowRunAssets with option to export selected ones to project-level Assets. UI shows: file name, producing step, file size. Actions: [Export to Project] per file or [Export All].

9. **AC9: Export asset tool** — The `export_asset` internal tool allows agents to promote files from `/workspace/outputs/` to project-level Assets during workflow execution. Tool creates WorkflowRunAsset + optionally creates/updates project Asset with new AssetVersion. Supports: tags, folder, public toggle.

10. **AC10: Workspace preparator service** — `WorkspacePreparator` service handles all file operations for step workspace setup: download WorkflowRunAssets from S3 → mount to `/workspace/input/`, download project Assets → mount, generate `_index.md`, resolve variables in instructions.

## Tasks / Subtasks

- [ ] Task 1: Output collection service (AC: #1)
  - [ ] 1.1 `WorkflowOutputCollector` service: scans `/workspace/outputs/`, uploads to S3 via Shrine
  - [ ] 1.2 Creates WorkflowRunAsset records for each collected file
  - [ ] 1.3 Integrate into `CompleteStepActivity`
- [ ] Task 2: Workspace preparator (AC: #2, #3, #10)
  - [ ] 2.1 `WorkspacePreparator` service
  - [ ] 2.2 Download and mount WorkflowRunAssets from previous steps
  - [ ] 2.3 Download and mount user-selected project Assets
  - [ ] 2.4 Generate `_index.md` with file descriptions
  - [ ] 2.5 Integrate into `PrepareStepActivity`
- [ ] Task 3: Variable replacement (AC: #4)
  - [ ] 3.1 Parse `{{variable}}` patterns in step instructions
  - [ ] 3.2 Resolve against available WorkflowRunAsset and Asset names
  - [ ] 3.3 Replace with actual paths
- [ ] Task 4: Input validation (AC: #5)
  - [ ] 4.1 Check `input_asset_specs` against available assets
  - [ ] 4.2 Interactive mode: prompt user for missing required inputs
  - [ ] 4.3 Non-interactive mode: log warning, proceed
- [ ] Task 5: Output validation (AC: #6)
  - [ ] 5.1 `OutputValidator` service: check existence, naming, structure, size
  - [ ] 5.2 On failure: apply on_failure policy (retry/skip/fail)
  - [ ] 5.3 Integrate into `CompleteStepActivity`
- [ ] Task 6: Provenance tracking (AC: #7)
  - [ ] 6.1 WorkflowRunAsset records include produced_by_step_run_id
  - [ ] 6.2 On export to project Asset: copy provenance to AssetVersion
- [ ] Task 7: Post-workflow asset review UI (AC: #8)
  - [ ] 7.1 `WorkflowAssetsReview` component
  - [ ] 7.2 List all WorkflowRunAssets grouped by step
  - [ ] 7.3 Export to project action per file or bulk
  - [ ] 7.4 Export API endpoint
- [ ] Task 8: Export asset tool (AC: #9)
  - [ ] 8.1 Internal tool: `export_asset(file, tags, folder, public)`
  - [ ] 8.2 Creates or updates project Asset with new AssetVersion
  - [ ] 8.3 Register as MCP tool or internal HTTP tool
- [ ] Task 9: Export to project API endpoint
  - [ ] 9.1 `POST /api/v1/company/projects/:project_id/workflows/runs/:run_id/assets/:asset_id/export`
  - [ ] 9.2 Creates project Asset from WorkflowRunAsset
  - [ ] 9.3 Supports options: folder, tags, public
- [ ] Task 10: Write tests
  - [ ] 10.1 Output collection: files collected → WorkflowRunAssets created
  - [ ] 10.2 Workspace preparation: assets mounted correctly, _index.md generated
  - [ ] 10.3 Variable replacement: {{artifact}} → path resolution
  - [ ] 10.4 Input/output validation
  - [ ] 10.5 Export to project: WorkflowRunAsset → Asset with version
  - [ ] 10.6 Provenance tracking: source info preserved through export

## Dev Notes

### Architecture

This story connects the entire artifact pipeline: outputs from one step become inputs for the next, with validation, tracking, and export capabilities.

**File flow:**
```
Step N completes:
  /workspace/outputs/architecture.md  ─→ S3 upload ─→ WorkflowRunAsset record
  /workspace/outputs/diagrams/flow.png ─→ S3 upload ─→ WorkflowRunAsset record

Step N+1 starts:
  WorkflowRunAsset (architecture.md)  ─→ S3 download ─→ /workspace/input/architecture.md
  WorkflowRunAsset (flow.png)         ─→ S3 download ─→ /workspace/input/diagrams/flow.png
  Project Asset (prd.md)              ─→ S3 download ─→ /workspace/input/prd.md
  Auto-generated                      ─→              ─→ /workspace/input/_index.md
```

**Key services:**
1. `WorkflowOutputCollector` — collects files from container's `/workspace/outputs/`
2. `WorkspacePreparator` — sets up `/workspace/input/` for next step
3. `OutputValidator` — validates output against specs
4. `AssetExportService` — promotes WorkflowRunAsset to project-level Asset

**S3 key pattern for WorkflowRunAssets:**
`workflow_runs/{workflow_run_id}/steps/{step_run_id}/{filename}`

**_index.md template:**
```markdown
# Workspace Input Index

## Project Assets (selected at workflow start)
- **prd.md** — Product Requirements Document (document, 2.3KB)
- **repo/** — Repository: github.com/acme/backend (repository, branch: main)

## Workflow Run Assets (from previous steps)
- **architecture.md** — from Step 1 "Create Architecture" (document, 15.2KB)
- **security_findings.json** — from Step 1 "Create Architecture" (data, 3.4KB)

## Instructions
- Read from: /workspace/input/
- Save all results to: /workspace/outputs/
- If you need to modify an existing document, copy from input to outputs first
```

**Output validation levels:**
1. Existence — file must exist in outputs
2. Naming — file name matches pattern (e.g., `*.md`)
3. Structure — for markdown: required sections present (regex check)
4. Size — minimum byte/line count

Validation is optional — only runs if `output_asset_specs` are defined on the Step.

### Key files to create

**Backend:**
- `app/services/workflow_output_collector.rb`
- `app/services/workspace_preparator.rb`
- `app/services/output_validator.rb`
- `app/services/asset_export_service.rb`
- `app/controllers/api/v1/company/projects/workflows/runs/assets_controller.rb`

**Frontend:**
- `app/frontend/features/workflow-execution/ui/WorkflowAssetsReview.tsx`
- `app/frontend/features/workflow-execution/ui/ExportAssetDialog.tsx`

### Key files to modify

- `app/temporal/activities/workflow/prepare_step_activity.rb` — use WorkspacePreparator
- `app/temporal/activities/workflow/complete_step_activity.rb` — use WorkflowOutputCollector + OutputValidator
- `app/models/workflow_run_asset.rb` — add Shrine uploader
- `app/serializers/workflow_run_serializer.rb` — include assets

### Important: File collection from container

Output collection must happen BEFORE container cleanup (same pattern as session log/output collection in Story 16-2/16-4). The flow:
1. Agent finishes (container still running)
2. `before_cleanup` phase → collect outputs from container
3. Upload to S3 → create WorkflowRunAsset records
4. `cleanup` phase → stop and remove container

This mirrors the existing `collect_outputs` flow in `AgentSessionStrategy#before_cleanup`.

### Dependencies

- Story 12-6 (WorkflowRun, WorkflowRunAsset models)
- Story 12-7 (Interactive execution flow)
- Story 12-8 (Non-interactive execution)
- Epic 11 done (Asset model, S3 upload, Shrine)
- Story 16-4 (collect_outputs pattern — reference implementation)

### Testing

- End-to-end: step 1 produces output → step 2 sees it in /workspace/input/
- _index.md: correct format, lists all assets with sources
- Variable replacement: {{prd}} resolves to /workspace/input/prd.md
- Output validation: missing required output → on_failure policy triggered
- Export: WorkflowRunAsset → project Asset with correct version and provenance
- Collection from container: files extracted before cleanup

### References

- [Source: ai/workflow-architecture.md#2.7](ai/workflow-architecture.md) — WorkflowRunAsset model
- [Source: ai/workflow-architecture.md#3](ai/workflow-architecture.md) — Workspace Structure
- [Source: ai/workflow-architecture.md#4.3](ai/workflow-architecture.md) — Complete Step / output collection
- [Source: ai/workflow-architecture.md#6.4](ai/workflow-architecture.md) — export_asset tool
- [Source: ai/workflow-architecture.md#7](ai/workflow-architecture.md) — Asset versioning
- [Source: ai/workflow-architecture.md#9](ai/workflow-architecture.md) — Output validation
- [Source: ai/prd/functional-requirements.md#FR18](ai/prd/functional-requirements.md) — FR18: System passes artifacts between steps
- [Source: ai/prd/functional-requirements.md#FR25](ai/prd/functional-requirements.md) — FR25: Workflow steps reference previous artifacts
- [Source: app/services/container_strategies/agent_session_strategy.rb](app/services/container_strategies/agent_session_strategy.rb) — before_cleanup output collection pattern

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
