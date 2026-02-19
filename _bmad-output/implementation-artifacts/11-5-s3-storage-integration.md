# Story 11.5: S3 Storage Integration

Status: review

## Story

As a project member,
I want files to upload directly to S3 from the browser with progress indicators,
so that large files upload fast without going through the Rails server.

## Acceptance Criteria

1. **Presign endpoint** — `GET /api/v1/company/projects/:project_id/assets/presign?filename=X&type=Y` returns S3 presigned POST data (url, fields).
2. **Direct browser-to-S3 upload** — Frontend uses Uppy with `@uppy/aws-s3` to upload directly to S3, then sends cached file data to Rails create endpoint.
3. **S3 key structure** — Files stored at `store/{scope_type}/{scope_id}/assets/{asset_id}/{version}/{filename}`.
4. **Progress indicator** — Uppy provides upload progress in the UploadAssetDialog.
5. **Access control** — S3 presigned URLs scoped to authenticated users only. Presign endpoint requires authentication.
6. **Dev environment** — In development, upload goes through Rails (FileSystem storage) — Uppy falls back to regular upload. No presign needed.

## Tasks / Subtasks

- [x] Task 1: Presign endpoint (AC: #1, #5)
  - [x] 1.1 Add presign route: `collection { get :presign }` on assets resources
  - [x] 1.2 Implement presign action in Api::V1::AssetsController with auth
  - [x] 1.3 Return `{ url, fields, method, headers }` for Uppy S3 plugin

- [x] Task 2: Custom S3 key (AC: #3)
  - [x] 2.1 Override `AssetFileUploader#generate_location` for meaningful S3 paths
  - [x] 2.2 Path format: `{scope_type_lower}/{scope_id}/assets/{asset_id}/v{version}/{filename}`

- [x] Task 3: Frontend Uppy integration (AC: #2, #4)
  - [x] 3.1 Rewrote `UploadAssetDialog.tsx` with Uppy + @uppy/aws-s3
  - [x] 3.2 After upload, extract cached file data from uploadURL and send to Rails create endpoint
  - [x] 3.3 Progress bar via LinearProgress + Uppy upload-progress events

- [x] Task 4: Environment handling (AC: #6)
  - [x] 4.1 Dev/test presign returns local upload endpoint URL; prod returns S3 presigned POST
  - [x] 4.2 Transparent to frontend — same Uppy flow for all environments

- [x] Task 5: Tests (AC: all)
  - [x] 5.1 Presign endpoint test — returns valid presign data, requires auth
  - [x] 5.2 Upload endpoint test — stores file, returns location, requires auth
  - [x] 5.3 Custom S3 key test — verify path format in generate_location

## Dev Notes

### Shrine Presign

Shrine has `presign_endpoint` plugin already configured in `web/config/initializers/shrine.rb`. The existing config references `upload_api_v1_assets_path` which doesn't exist yet — this story creates it.

```ruby
# In shrine.rb, production:
Shrine.plugin(:presign_endpoint, presign_options: ->(request) {
  filename = request.params["filename"]
  type = request.params["type"]
  {
    content_disposition: ContentDisposition.inline(filename),
    content_type: type,
    content_length_range: 0..(1024 * 1024 * 1024)
  }
})
```

### Uppy Integration

`@uppy/aws-s3` is already in `package.json`. Pattern:
```typescript
import Uppy from '@uppy/core'
import AwsS3 from '@uppy/aws-s3'

const uppy = new Uppy().use(AwsS3, {
  getUploadParameters: async (file) => {
    const { url, fields } = await presignAsset({ filename: file.name, type: file.type })
    return { method: 'POST', url, fields }
  }
})
```

### References

- [Source: web/config/initializers/shrine.rb] — Existing Shrine S3 config
- [Source: web/package.json] — @uppy/aws-s3 dependency
- [Source: web/app/uploaders/asset_file_uploader.rb] — Uploader to extend

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Completion Notes List
- Presign endpoint with authentication at `GET /api/v1/assets/presign`
- Dev upload endpoint at `POST /api/v1/assets/upload` using Shrine's upload_response
- Custom S3 key: `{scope_type}/{scope_id}/assets/{asset_id}/v{version}/{filename}`
- Frontend: UploadAssetDialog rewritten with Uppy + @uppy/aws-s3 (shouldUseMultipart: false)
- Upload flow: Uppy presign → upload to S3/local → extract cached data → send to create API
- Progress bar via MUI LinearProgress + Uppy upload-progress events
- API changed from FormData to JSON body with `file: { id, storage }` (Shrine cached file data)
- All 356 asset-related tests pass (15 new tests added)

### File List
- `web/config/routes.rb` — added presign + upload collection routes
- `web/app/controllers/api/v1/assets_controller.rb` — new: presign + upload actions
- `web/app/uploaders/asset_file_uploader.rb` — added generate_location for S3 key
- `web/app/frontend/features/assets-management/ui/UploadAssetDialog.tsx` — rewritten with Uppy
- `web/app/frontend/features/assets-management/api/assetsApi.ts` — JSON body instead of FormData
- `web/app/frontend/features/assets-management/lib/types.ts` — CachedFileData interface
- `web/app/frontend/shared/api/routes.ts` — regenerated with presign/upload routes
- `web/test/controllers/api/v1/assets_controller_test.rb` — new: presign + upload tests
- `web/test/models/asset_version_test.rb` — added generate_location test
- `web/test/fixtures/files/test_file.txt` — test fixture file
