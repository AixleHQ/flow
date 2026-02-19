# Story 11.4: Delete Artifacts

Status: review

## Story

As a project member,
I want to soft-delete assets with the ability to restore them,
so that accidental deletions can be recovered.

## Acceptance Criteria

1. **Soft delete** — `destroy` action sets `deleted_at` timestamp instead of hard delete. Asset no longer appears in index/merged queries.
2. **Restore endpoint** — `POST /api/v1/.../assets/:id/restore` clears `deleted_at`, asset reappears.
3. **Retention period** — Assets auto-purged after 30 days (background job or manual cleanup — job implementation deferred).
4. **Trash view** — API endpoint to list deleted assets: `GET .../assets?q[deleted]=true`.
5. **Frontend confirmation** — Delete dialog shows asset name, version count. Warns if asset has multiple versions.
6. **Frontend restore** — Trash section with restore button (can be in separate story for UI, but API must be ready).

## Tasks / Subtasks

- [x] Task 1: Database migration (AC: #1)
  - [x] 1.1 Add `deleted_at: datetime` column to assets table (nullable)
  - [x] 1.2 Add index on `deleted_at` for efficient trash queries

- [x] Task 2: Model soft delete (AC: #1, #2)
  - [x] 2.1 Add explicit `scope :active` and `scope :deleted` to Asset
  - [x] 2.2 Add `soft_delete!` method — sets `deleted_at`
  - [x] 2.3 Add `restore!` method — clears `deleted_at`
  - [x] 2.4 Add `deleted?` helper
  - [x] 2.5 Update `for_company`, `for_project`, `accessible_from_project`, `merged_for_project` to exclude deleted assets

- [x] Task 3: Controller updates (AC: #2, #4)
  - [x] 3.1 Change `destroy` action to call `soft_delete!`
  - [x] 3.2 Add `restore` member action
  - [x] 3.3 Add `restore` route: `member { post :restore }`
  - [x] 3.4 Support `?q[deleted]=true` filter for trash view in company index
  - [x] 3.5 Add `restore?` policy method

- [x] Task 4: Frontend (AC: #5, #6)
  - [x] 4.1 Update `DeleteAssetDialog.tsx` to show version count warning + soft-delete messaging
  - [x] 4.2 Add `restoreCompanyAsset` and `restoreProjectAsset` mutations to `assetsApi.ts`

- [x] Task 5: Tests (AC: all)
  - [x] 5.1 Model test — soft_delete!, restore!, deleted?, active/deleted scopes, for_company/for_project exclude deleted
  - [x] 5.2 Controller test — destroy sets deleted_at, restore clears it, index excludes deleted, trash filter
  - [x] 5.3 Test that merged_for_project and accessible_from_project exclude deleted assets

## Dev Notes

### Soft Delete Approach

Used **explicit scopes** (not `default_scope`) — `scope :active` and `scope :deleted`. All existing scopes (`for_company`, `for_project`, `accessible_from_project`) chain `.active` to exclude soft-deleted records.

### Retention / Purge

Auto-purge after 30 days is deferred. The `deleted_at` timestamp allows future background job.

## Dev Agent Record

### Agent Model Used
Claude claude-4.6-opus-max-thinking

### Debug Log References
No errors encountered.

### Completion Notes List
- Migration adds `deleted_at` datetime column with index
- Model uses explicit `active`/`deleted` scopes (no default_scope)
- `soft_delete!` sets timestamp, `restore!` clears it
- All existing scopes chain `.active` automatically
- Company controller supports `?q[deleted]=true` for trash view
- Both company and project controllers have `restore` action with policy
- Frontend `DeleteAssetDialog` shows version count warning and soft-delete messaging
- RTK Query restore mutations added for both scopes
- 87 asset-related tests pass with 0 failures

### File List
- web/db/migrate/20260218100005_add_deleted_at_to_assets.rb (new)
- web/app/models/asset.rb (modified — soft delete scopes/methods)
- web/app/controllers/api/v1/company/assets_controller.rb (modified — soft delete, restore, trash filter)
- web/app/controllers/api/v1/company/projects/assets_controller.rb (modified — soft delete, restore)
- web/config/routes.rb (modified — restore routes)
- web/app/policies/api/v1/company/assets_policy.rb (modified — restore?)
- web/app/policies/api/v1/company/projects/assets_policy.rb (modified — restore?)
- web/app/frontend/features/assets-management/api/assetsApi.ts (modified — restore mutations)
- web/app/frontend/features/assets-management/ui/DeleteAssetDialog.tsx (modified — soft-delete messaging)
- web/app/frontend/shared/api/routes.ts (regenerated — restore routes)
- web/test/models/asset_test.rb (modified — soft delete tests)
- web/test/controllers/api/v1/company/assets_controller_test.rb (modified — destroy/restore/trash tests)
