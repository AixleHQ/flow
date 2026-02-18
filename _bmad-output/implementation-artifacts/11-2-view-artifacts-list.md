# Story 11.2: View Artifacts List

Status: review

## Story

As a project member,
I want to view all assets in my project (including company-shared ones),
so that I can find and manage files used in sessions and workflows.

## Acceptance Criteria

1. **Assets page** in project context — lists all assets via `merged_for_project` (company + project assets with scope indicators).
2. **Company assets tab** — company admin can view/manage company-level assets.
3. **Table view** — columns: Name, Folder, Type, Size, Version, Uploader, Date, Scope, Actions.
4. **Search and filter** — Ransack-powered: filter by name, folder, asset_type. Client-side search.
5. **Upload dialog** — form with file picker, name (auto-from filename), asset_type selector, folder selector/input. Creates asset + first version via API.
6. **Edit metadata** — dialog to update folder, tags, public flag, asset_type.
7. **Delete with confirmation** — delete dialog, removes asset and all versions.
8. **RTK Query integration** — cache with proper invalidation on CRUD operations.

## Tasks / Subtasks

- [x] Task 1: RTK Query API layer (AC: #8)
  - [x] 1.1 Add `QueryTag.Assets` to `shared/api/QueryTag.ts`
  - [x] 1.2 Create `features/assets-management/api/assetsApi.ts` — all CRUD endpoints
  - [x] 1.3 Backend routes auto-generated via `rake ts:routes`

- [x] Task 2: Types and schemas (AC: #5, #6)
  - [x] 2.1 Create `features/assets-management/lib/types.ts`
  - [x] 2.2 Create `features/assets-management/lib/assetSchema.ts`

- [x] Task 3: Assets page for project (AC: #1, #3, #4)
  - [x] 3.1 Create `features/assets-management/ui/AssetsPage.tsx`
  - [x] 3.2 Create `features/assets-management/ui/AssetsTable.tsx`
  - [x] 3.3 Create `pages/assets/index.ts` and `pages/assets/ui/AssetsPage.tsx`
  - [x] 3.4 Create `AssetScopeBadge.tsx` and `AssetTypeBadge.tsx`

- [x] Task 4: Upload dialog (AC: #5)
  - [x] 4.1 Create `features/assets-management/ui/UploadAssetDialog.tsx`

- [x] Task 5: Edit and Delete dialogs (AC: #6, #7)
  - [x] 5.1 Create `features/assets-management/ui/EditAssetDialog.tsx`
  - [x] 5.2 Create `features/assets-management/ui/DeleteAssetDialog.tsx`

- [x] Task 6: Routing (AC: #1, #2)
  - [x] 6.1 Project assets: integrated as "artifacts" tab in ProjectPage
  - [x] 6.2 Add company assets route to `app/routeTree.tsx`
  - [x] 6.3 Add `companyAssetsPath` to `shared/routes.ts`
  - [x] 6.4 Add navigation link in AppHeader nav items

## Dev Notes

### Backend Already Done (11-1)

All backend API is implemented:
- `GET /api/v1/company/assets` — company assets (ransack)
- `GET /api/v1/company/projects/:id/assets` — merged project assets
- `POST/PATCH/DELETE` on both levels
- `AssetSerializer` returns: id, name, asset_type, folder, tags, public, scope_type, scope_id, scope_indicator, latest_version (id, version, content_type, file_size, uploaded_by_id, created_at), versions_count

### Frontend Pattern Reference

Follow `features/skills-management/` structure exactly:
- `web/app/frontend/features/skills-management/api/skillsApi.ts` — RTK Query pattern
- `web/app/frontend/features/skills-management/ui/SkillsPage.tsx` — page component pattern
- `web/app/frontend/features/skills-management/ui/SkillsTable.tsx` — table pattern
- `web/app/frontend/features/skills-management/ui/SkillFormDialog.tsx` — form dialog pattern
- `web/app/frontend/features/skills-management/lib/types.ts` — types pattern
- `web/app/frontend/shared/api/QueryTag.ts` — add Assets tag
- `web/app/frontend/shared/routes.ts` — route helpers

### File Upload Notes

- Upload is a standard multipart POST with `file` param via Shrine's `cached_attachment_data` flow
- `@uppy/aws-s3` is in package.json but NOT required for this story — simple file input is sufficient
- Direct S3 upload (Uppy + presigned URLs) deferred to 11-5

### Project Structure

- `web/app/frontend/features/assets-management/api/assetsApi.ts`
- `web/app/frontend/features/assets-management/ui/AssetsPage.tsx`
- `web/app/frontend/features/assets-management/ui/AssetsTable.tsx`
- `web/app/frontend/features/assets-management/ui/UploadAssetDialog.tsx`
- `web/app/frontend/features/assets-management/ui/EditAssetDialog.tsx`
- `web/app/frontend/features/assets-management/ui/DeleteAssetDialog.tsx`
- `web/app/frontend/features/assets-management/lib/types.ts`
- `web/app/frontend/features/assets-management/lib/assetSchema.ts`
- `web/app/frontend/pages/assets/index.ts`
- `web/app/frontend/pages/assets/ui/AssetsPage.tsx`

### References

- [Source: web/app/frontend/features/skills-management/] — Full reference for Feature-Slice pattern
- [Source: web/app/serializers/api/v1/asset_serializer.rb] — API response shape
- [Source: web/app/controllers/api/v1/company/projects/assets_controller.rb] — Backend endpoints

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Debug Log References
- TypeScript compilation: passed with 0 errors
- Lint check: all new files clean

### Completion Notes List
- Followed skills-management pattern exactly for Feature-Slice Design
- File upload uses FormData (not JSON) with isDecamelize:false for correct Rails nested params
- Auto-guesses asset type from file extension in upload dialog
- Project assets shown via existing "artifacts" tab in ProjectPage (replaced mock data)
- Company assets accessible via new /company/assets route in AppHeader (admin-only)
- Client-side filtering by name, folder, and asset_type
- Folder filter dynamically populated from existing asset folders

### File List
- web/app/frontend/shared/api/QueryTag.ts (modified - added Assets tag)
- web/app/frontend/shared/api/routes.ts (regenerated - includes asset route helpers)
- web/app/frontend/shared/routes.ts (modified - added companyAssetsPath)
- web/app/frontend/features/assets-management/index.ts (new)
- web/app/frontend/features/assets-management/api/assetsApi.ts (new)
- web/app/frontend/features/assets-management/lib/types.ts (new)
- web/app/frontend/features/assets-management/lib/assetSchema.ts (new)
- web/app/frontend/features/assets-management/ui/AssetsPage.tsx (new)
- web/app/frontend/features/assets-management/ui/AssetsTable.tsx (new)
- web/app/frontend/features/assets-management/ui/AssetScopeBadge.tsx (new)
- web/app/frontend/features/assets-management/ui/AssetTypeBadge.tsx (new)
- web/app/frontend/features/assets-management/ui/UploadAssetDialog.tsx (new)
- web/app/frontend/features/assets-management/ui/EditAssetDialog.tsx (new)
- web/app/frontend/features/assets-management/ui/DeleteAssetDialog.tsx (new)
- web/app/frontend/pages/assets/index.ts (new)
- web/app/frontend/pages/assets/ui/AssetsPage.tsx (new)
- web/app/frontend/app/routeTree.tsx (modified - added companyAssetsRoute)
- web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx (modified - added Assets nav item)
- web/app/frontend/pages/project/ui/ProjectPage.tsx (modified - replaced mock artifacts with AssetsPanel)
