# Story 11.3: Download Artifacts

Status: review

## Story

As a project member,
I want to download asset files preserving their original filename,
so that I can use them locally.

## Acceptance Criteria

1. **Show endpoint** — `GET /api/v1/company/projects/:project_id/assets/:id` returns asset details with all versions.
2. **Download endpoint** — `GET /api/v1/company/projects/:project_id/assets/:id/download` returns the latest version file. `GET .../download?version=N` returns specific version.
3. **Presigned URL** — In production (S3), returns redirect to presigned URL with `Content-Disposition: attachment; filename="original.md"`. In dev, streams file directly.
4. **Frontend download** — Download button on each asset row in AssetsTable. Opens file in new tab or triggers browser download.
5. **Bulk download** — deferred (out of scope for this story, noted for future).

## Tasks / Subtasks

- [x] Task 1: Backend show + download actions (AC: #1, #2, #3)
  - [x] 1.1 Add `show` and `download` actions to both controllers
  - [x] 1.2 Add routes with member download route
  - [x] 1.3 Add show/download to policies
  - [x] 1.4 Fix: move AssetSerializer to Api::V1 namespace (was incorrectly at root)

- [x] Task 2: Asset show serializer (AC: #1)
  - [x] 2.1 Create `Api::V1::AssetDetailSerializer` inheriting from AssetSerializer with full versions array including file_url

- [x] Task 3: Frontend download (AC: #4)
  - [x] 3.1 Download via direct `<a href>` to download endpoint (no RTK Query needed)
  - [x] 3.2 Download button added to AssetsTable row actions
  - [x] 3.3 Regenerated TS route helpers

- [x] Task 4: Tests (AC: all)
  - [x] 4.1 Company assets controller test — show, download, auth, 404
  - [x] 4.2 Project assets controller test — show (project + company assets), download, version resolution, auth
  - [x] 4.3 Added :with_file trait to asset_version factory

## Dev Notes

### Shrine File URL

Shrine provides `file.url` which returns:
- Dev (FileSystem): local path like `http://localhost:3000/store/asset_version/1/file/test.md`
- Production (S3): presigned URL with expiration (configured 24h in `shrine.rb`)

For download with proper filename:
```ruby
def download
  asset = current_project.assets.find(params[:id])
  version = resolve_version(asset)
  redirect_to version.file_url(
    response_content_disposition: ContentDisposition.attachment(asset.name)
  ), allow_other_host: true
end
```

### Existing Patterns

- `web/config/initializers/shrine.rb` — S3 presigned URL config (24h expiration, content_disposition support)
- Routes: add `show` to existing `only:` array and member download route

### References

- [Source: web/config/initializers/shrine.rb] — Shrine URL configuration
- [Source: web/app/controllers/api/v1/company/projects/assets_controller.rb] — Extend existing controller

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Debug Log References
- 18 controller tests: all passing
- 40 existing model tests: no regressions
- TypeScript compilation: 0 errors

### Completion Notes List
- Fixed AssetSerializer namespace: moved from root to Api::V1 to match controller references
- Added `require "content_disposition"` to shrine.rb (was only loaded transitively in production S3 setup)
- Download action uses redirect_to with presigned URL (S3) or direct file URL (dev)
- Project download can access company-shared assets via find_accessible_asset query
- Added :with_file factory trait for controller tests that need actual file downloads

### File List
- web/app/serializers/api/v1/asset_serializer.rb (new — moved from root, added Api::V1 namespace)
- web/app/serializers/api/v1/asset_detail_serializer.rb (new)
- web/app/serializers/asset_serializer.rb (deleted — replaced by namespaced version)
- web/app/controllers/api/v1/company/assets_controller.rb (modified — added show, download)
- web/app/controllers/api/v1/company/projects/assets_controller.rb (modified — added show, download, find_accessible_asset, resolve_version)
- web/app/policies/api/v1/company/assets_policy.rb (modified — added show?, download?)
- web/app/policies/api/v1/company/projects/assets_policy.rb (modified — added show?, download?)
- web/config/routes.rb (modified — added show, download member routes)
- web/config/initializers/shrine.rb (modified — added require "content_disposition")
- web/app/frontend/shared/api/routes.ts (regenerated — added download route helpers)
- web/app/frontend/features/assets-management/ui/AssetsTable.tsx (modified — added download button)
- web/app/frontend/features/assets-management/ui/AssetsPage.tsx (modified — pass projectId to table)
- web/test/factories/asset_versions.rb (modified — added :with_file trait)
- web/test/controllers/api/v1/company/assets_controller_test.rb (new)
- web/test/controllers/api/v1/company/projects/assets_controller_test.rb (new)
