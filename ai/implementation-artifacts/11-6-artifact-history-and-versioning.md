# Story 11.6: Artifact History & Versioning

Status: review

## Story

As a project member,
I want to see version history of an asset and download any specific version,
so that I can track changes and access previous file revisions.

## Acceptance Criteria

1. **Versions API** — `GET /api/v1/company/projects/:project_id/assets/:id/versions` returns all versions with metadata (version number, size, content_type, uploaded_by, provenance, created_at, download_url).
2. **Upload new version** — Re-uploading to the same asset name creates a new AssetVersion (v2, v3, etc.) — this already works from 11-1.
3. **Download specific version** — `GET .../assets/:id/download?version=N` (from 11-3).
4. **Version history UI** — expandable panel or dialog showing all versions of an asset with: version number, upload date, uploader name, file size, download link.
5. **Current version badge** — AssetsTable shows current version number (e.g., "v3") per asset.

## Tasks / Subtasks

- [x] Task 1: Versions API endpoint (AC: #1)
  - [x] 1.1 Add `get :versions` member route on both company and project assets
  - [x] 1.2 Add `versions` action to both AssetsControllers
  - [x] 1.3 Create `Api::V1::AssetVersionSerializer` with file_url, provenance, etc.
  - [x] 1.4 Add `versions?` to both Pundit policies

- [x] Task 2: Frontend version history (AC: #4, #5)
  - [x] 2.1 Add `getCompanyAssetVersions` / `getProjectAssetVersions` queries
  - [x] 2.2 Create `VersionHistoryDialog` — table with versions, download links, "latest" badge, source
  - [x] 2.3 Version badge already present in AssetsTable (vN + count)
  - [x] 2.4 Add History button (HistoryIcon) to asset row actions

- [x] Task 3: Tests (AC: all)
  - [x] 3.1 Company versions: ordered desc, includes all fields, auth required
  - [x] 3.2 Project versions: project + company asset access, serializer fields, auth

## Dev Notes

### Already Implemented

- `AssetVersion` model with auto-increment, Shrine attachment, provenance jsonb
- `Asset#latest_version` method
- `AssetSerializer` already returns `latest_version` and `versions_count`
- Upload creates new version if asset with same name exists (11-1 create action)

### Versions Serializer

```ruby
class Api::V1::AssetVersionSerializer < ApplicationSerializer
  attributes :id, :version, :content_type, :file_size,
             :uploaded_by_id, :provenance, :file_url, :created_at

  def file_url
    object.file&.url
  end
end
```

### References

- [Source: web/app/models/asset_version.rb] — Existing model
- [Source: web/app/serializers/api/v1/asset_serializer.rb] — latest_version already serialized
- [Source: web/app/controllers/api/v1/company/projects/assets_controller.rb] — Parent controller pattern

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Completion Notes List
- `GET /api/v1/company/assets/:id/versions` and `GET .../projects/:project_id/assets/:id/versions`
- `AssetVersionSerializer` with file_url, provenance, content_type, file_size, uploaded_by_id
- `VersionHistoryDialog` with table: version number, date, size, type, source, download link
- "latest" chip badge on newest version in dialog
- History button (HistoryIcon) added to AssetsTable row actions
- Version badge (vN + count) was already in AssetsTable from story 11-2
- 365 asset-related tests pass (9 new versions tests)

### File List
- `web/config/routes.rb` — added `get :versions` member route on both asset resources
- `web/app/serializers/api/v1/asset_version_serializer.rb` — new serializer
- `web/app/controllers/api/v1/company/assets_controller.rb` — added `versions` action
- `web/app/controllers/api/v1/company/projects/assets_controller.rb` — added `versions` action
- `web/app/policies/api/v1/company/assets_policy.rb` — added `versions?`
- `web/app/policies/api/v1/company/projects/assets_policy.rb` — added `versions?`
- `web/app/frontend/features/assets-management/lib/types.ts` — added `DetailedAssetVersion`
- `web/app/frontend/features/assets-management/api/assetsApi.ts` — added versions queries
- `web/app/frontend/features/assets-management/ui/VersionHistoryDialog.tsx` — new component
- `web/app/frontend/features/assets-management/ui/AssetsTable.tsx` — added History button
- `web/app/frontend/features/assets-management/ui/AssetsPage.tsx` — wired VersionHistoryDialog
- `web/app/frontend/shared/api/routes.ts` — regenerated
- `web/test/controllers/api/v1/company/assets_controller_test.rb` — added versions tests
- `web/test/controllers/api/v1/company/projects/assets_controller_test.rb` — added versions tests
