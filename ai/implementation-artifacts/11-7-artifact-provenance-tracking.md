# Story 11.7: Artifact Provenance Tracking

Status: review

## Story

As a project member,
I want to see where each asset version came from (manual upload, workflow step, or GitHub),
so that I can understand the origin and trust level of each file.

## Acceptance Criteria

1. **Auto-populate provenance on upload** — When user uploads manually: `{ source: "upload", user_id: X, user_name: "..." }`. Controller sets this automatically.
2. **Workflow provenance** — When asset is created by workflow step (via `export_asset` tool): `{ source: "workflow", workflow_run_id: X, step_run_id: Y, step_name: "...", workflow_name: "..." }`. Set by workflow system (future epic 12).
3. **Provenance display** — Frontend shows human-readable provenance: "Uploaded by John on Feb 18, 2026" or "Created by workflow 'Product Planning' → step 'Create Architecture'".
4. **Provenance in version history** — Each version in VersionHistoryDialog shows its provenance.
5. **Provenance in asset detail** — Latest version provenance shown in AssetsTable or asset detail view.

## Tasks / Subtasks

- [x] Task 1: Auto-populate upload provenance (AC: #1)
  - [x] 1.1 Both controllers set `provenance = { source: "upload", user_id, user_name }` server-side
  - [x] 1.2 Removed `provenance: {}` from `version_params` — client cannot override

- [x] Task 2: Provenance display helpers (AC: #3)
  - [x] 2.1 `AssetVersion#provenance_summary` — handles upload, workflow, github, unknown
  - [x] 2.2 `provenance_summary` in `AssetVersionSerializer`
  - [x] 2.3 `provenance_summary` in `AssetSerializer#latest_version` and `AssetDetailSerializer#versions`

- [x] Task 3: Frontend provenance display (AC: #3, #4, #5)
  - [x] 3.1 Provenance subtitle under asset name in AssetsTable
  - [x] 3.2 Provenance column in VersionHistoryDialog
  - [x] 3.3 `provenanceSummary` field in `AssetVersion` type

- [x] Task 4: Tests (AC: all)
  - [x] 4.1 Model: provenance_summary for upload, workflow, github, unknown sources
  - [x] 4.2 Controller: create auto-sets upload provenance
  - [x] 4.3 Controller: client-provided provenance is ignored
  - [x] 4.4 Controller: versions endpoint includes provenance_summary

## Dev Notes

### Provenance Structure

Already stored as `jsonb` on AssetVersion. Current structure (from 11-1):
```ruby
# Manual upload
{ source: "upload", user_id: 1, user_name: "John" }

# Workflow (future, set by export_asset tool in Epic 12)
{ source: "workflow", workflow_run_id: 5, step_run_id: 12, step_name: "Create Architecture", workflow_name: "Product Planning" }

# GitHub (future, Epic 14)
{ source: "github", repo_url: "...", branch: "main", commit: "abc123" }
```

### Provenance Summary Method

```ruby
class AssetVersion < ApplicationRecord
  def provenance_summary
    case provenance&.dig("source")
    when "upload"
      "Uploaded by #{provenance['user_name'] || 'unknown'}"
    when "workflow"
      "Workflow '#{provenance['workflow_name']}' → #{provenance['step_name']}"
    when "github"
      "From #{provenance['repo_url']} (#{provenance['branch']})"
    else
      "Unknown source"
    end
  end
end
```

### Security Note

Controller must set provenance server-side, not trust client input:
```ruby
def create
  # ...
  version.provenance = { source: "upload", user_id: current_user.id, user_name: current_user.name }
  # ...
end
```

### References

- [Source: web/app/models/asset_version.rb] — Existing model with provenance jsonb
- [Source: web/app/controllers/api/v1/company/projects/assets_controller.rb] — Controller to update
- [Source: ai/workflow-architecture.md#2.8] — Provenance design

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Completion Notes List
- Upload provenance auto-populated server-side: `{ source: "upload", user_id, user_name }`
- `provenance: {}` removed from permitted params — client cannot inject provenance
- `provenance_summary` method handles: upload, workflow, github, unknown sources
- Summary included in all serializers (list, detail, versions)
- Frontend: provenance subtitle under asset name in table, provenance column in version history
- 374 asset-related tests pass (9 new: provenance_summary model tests + controller provenance tests)

### File List
- `web/app/models/asset_version.rb` — added `provenance_summary` method
- `web/app/controllers/api/v1/company/assets_controller.rb` — auto-set provenance, stripped from version_params
- `web/app/controllers/api/v1/company/projects/assets_controller.rb` — same changes
- `web/app/serializers/api/v1/asset_version_serializer.rb` — added provenance_summary
- `web/app/serializers/api/v1/asset_serializer.rb` — added provenance_summary to latest_version
- `web/app/serializers/api/v1/asset_detail_serializer.rb` — added provenance_summary to versions
- `web/app/frontend/features/assets-management/lib/types.ts` — added provenanceSummary to AssetVersion
- `web/app/frontend/features/assets-management/ui/AssetsTable.tsx` — provenance subtitle
- `web/app/frontend/features/assets-management/ui/VersionHistoryDialog.tsx` — provenance column
- `web/test/models/asset_version_test.rb` — 6 new provenance_summary tests
- `web/test/controllers/api/v1/company/assets_controller_test.rb` — 3 new provenance tests
