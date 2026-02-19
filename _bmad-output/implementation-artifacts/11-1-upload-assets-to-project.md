# Story 11.1: Upload Assets to Project

Status: review

## Story

As a project member,
I want to upload files (documents, images, archives, code) to a project or company,
so that I can store and share assets for use in sessions and workflows.

## Acceptance Criteria

1. **Asset + AssetVersion models with polymorphic scope** — Asset uses `belongs_to :scope, polymorphic: true` (Company | Project), same pattern as Agent/Tool/Skill. AssetVersion is a separate model holding file data (s3_key, content_type, file_size, version number).
2. **Upload via Shrine** — Files uploaded through existing Shrine infrastructure (S3 in production, FileSystem in dev, Memory in test). New `AssetFileUploader` for asset files.
3. **API endpoints** — Company-level and project-level CRUD controllers following existing namespace pattern (`Api::V1::Company::AssetsController`, `Api::V1::Company::Projects::AssetsController`).
4. **Versioning** — Uploading a file with the same name to the same scope creates a new AssetVersion (auto-incrementing version number), not a new Asset.
5. **Merged query** — `Asset.merged_for_project(project)` returns company + project assets with `scope_indicator`, same as Skill/Tool pattern.
6. **Authorization** — Pundit policies at company and project levels, matching existing patterns.
7. **Serialization** — Asset serializer includes latest version info (file_size, content_type, version, uploaded_at). Nested versions endpoint or inclusion optional.

## Tasks / Subtasks

- [x] Task 1: Database migrations (AC: #1)
  - [x] 1.1 Create `assets` table (name, asset_type, folder, tags, public, public_token, scope_type, scope_id, created_by_id, step_run_id, timestamps)
  - [x] 1.2 Create `asset_versions` table (asset_id, version, s3_key, content_type, file_size, file_data, uploaded_by_id, provenance, timestamps)
  - [x] 1.3 Add indexes: `[scope_type, scope_id, name]` unique, `[scope_type, scope_id]`, asset_versions `[asset_id, version]` unique

- [x] Task 2: Asset model (AC: #1, #4, #5)
  - [x] 2.1 `belongs_to :scope, polymorphic: true`, `belongs_to :created_by, class_name: 'User'`, `belongs_to :step_run, optional: true`
  - [x] 2.2 `has_many :versions, class_name: 'AssetVersion', dependent: :destroy`
  - [x] 2.3 Validations: scope_type inclusion `%w[Company Project]`, name uniqueness within scope
  - [x] 2.4 Enumerize `asset_type`: document, image, archive, code, diagram, data, html, repository, other
  - [x] 2.5 Scopes: `for_company`, `for_project`, `merged_for_project` with scope_indicator
  - [x] 2.6 Add `has_many :assets, as: :scope, dependent: :destroy` to Company and Project models

- [x] Task 3: AssetVersion model (AC: #1, #2, #4)
  - [x] 3.1 `belongs_to :asset`, `belongs_to :uploaded_by, class_name: 'User'`
  - [x] 3.2 `include AssetFileUploader::Attachment(:file)` — Shrine attachment
  - [x] 3.3 Auto-increment version within asset on creation
  - [x] 3.4 Provenance jsonb: `{ source: "upload", user_id: X }` or `{ source: "workflow", step_run_id: Y }`

- [x] Task 4: AssetFileUploader (AC: #2)
  - [x] 4.1 New Shrine uploader `app/uploaders/asset_file_uploader.rb`
  - [x] 4.2 Plugins: activerecord, determine_mime_type, pretty_location, restore_cached_data, cached_attachment_data, validation_helpers
  - [x] 4.3 Validation: max size 1GB, no mime type restriction (all file types allowed)

- [x] Task 5: API Controllers (AC: #3, #4)
  - [x] 5.1 `Api::V1::Company::AssetsController` — index, create, update, destroy (company-scoped)
  - [x] 5.2 `Api::V1::Company::Projects::AssetsController` — index (merged), create, update, destroy (project-scoped)
  - [x] 5.3 Create action: if asset with same name exists in scope → create new AssetVersion; else → create Asset + first AssetVersion
  - [x] 5.4 Routes: add `resources :assets` to company and project namespaces

- [x] Task 6: Serializer (AC: #7)
  - [x] 6.1 `Api::V1::AssetSerializer` — id, name, asset_type, folder, tags, public, scope_type, scope_id, scope_indicator, created_by, latest_version (version, file_size, content_type, uploaded_at, uploaded_by), versions_count

- [x] Task 7: Policies (AC: #6)
  - [x] 7.1 `Api::V1::Company::AssetsPolicy` — admin only (matches existing company policies)
  - [x] 7.2 `Api::V1::Company::Projects::AssetsPolicy` — project_accessible? (matches existing project policies)

- [x] Task 8: Tests (AC: all)
  - [x] 8.1 Asset model test — 23 tests: validations, scopes, merged_for_project, scope_indicator, latest_version, associations, cascading destroy
  - [x] 8.2 AssetVersion model test — 11 tests: auto-increment version, associations, provenance, DB uniqueness
  - [x] 8.3 Factory: `asset` and `asset_version` factories

## Dev Notes

### Architecture Decision: scope + AssetVersion

**Discussed and agreed**: Assets use the same polymorphic `scope` pattern as Agent/Tool/Skill/MCPServer/ConfigItem. `scope` = "who can access" (Company or Project). Company-scoped assets are shared to all projects via `merged_for_project`.

**Versioning is a separate model** (`AssetVersion`), not self-referential parent chain. Rationale: Asset holds metadata (name, type, folder, tags, public settings) which shouldn't be duplicated per version. Each version = one file in S3.

**`step_run_id`** on Asset (optional) — provenance link to workflow StepRun when asset is produced by a workflow step. Not a scope — just a reference for traceability. StepRun model does not exist yet; use `bigint` column without FK constraint for now.

### Existing Patterns to Follow

**Model pattern** — Follow `Skill` model exactly:
- `web/app/models/skill.rb` — polymorphic scope, for_company/for_project scopes, merged_for_project with scope_indicator
- No `kind` enum needed for Asset (no internal/custom distinction — all assets are user-created)

**Controller pattern** — Follow `web/app/controllers/api/v1/company/skills_controller.rb` and `web/app/controllers/api/v1/company/projects/skills_controller.rb`:
- Company controller: `current_company.assets.ransack(params[:q]).result`
- Project controller: `Asset.merged_for_project(current_project)` for index, `current_project.assets` for create/update/destroy

**Serializer pattern** — Follow `web/app/serializers/api/v1/skill_serializer.rb`:
- `scope_indicator` method with fallback logic
- Extend with `latest_version` virtual attribute

**Policy pattern** — Follow `web/app/policies/api/v1/company/skills_policy.rb` and `web/app/policies/api/v1/company/projects/skills_policy.rb`

**Shrine pattern** — Follow `web/app/uploaders/logo_uploader.rb` and `web/config/initializers/shrine.rb`:
- Shrine already configured for S3 (production) / FileSystem (dev) / Memory (test)
- `AssetFileUploader` similar to `LogoUploader` but without image processing
- Test helpers in `web/test/support/upload_support.rb`

**Routes pattern** — Add to `web/config/routes.rb` in existing namespace blocks:
```ruby
# Inside namespace :company
resources :assets, only: %i[index create update destroy]
# Inside scope module: :projects
resources :assets, only: %i[index create update destroy]
```

### Database Schema

```ruby
# Migration: CreateAssets
create_table :assets do |t|
  t.string :name, null: false
  t.string :asset_type, null: false, default: "document"
  t.string :folder                    # optional one-level grouping
  t.string :tags, array: true, default: []  # postgres array
  t.boolean :public, default: false
  t.string :public_token              # generated when public=true
  t.string :scope_type, null: false   # Company | Project
  t.bigint :scope_id, null: false
  t.bigint :created_by_id, null: false
  t.bigint :step_run_id              # optional provenance to workflow step
  t.timestamps
end
add_index :assets, %i[scope_type scope_id name], unique: true
add_index :assets, %i[scope_type scope_id]
add_index :assets, :created_by_id
add_index :assets, :step_run_id, where: "step_run_id IS NOT NULL"
add_foreign_key :assets, :users, column: :created_by_id

# Migration: CreateAssetVersions
create_table :asset_versions do |t|
  t.references :asset, null: false, foreign_key: true
  t.integer :version, null: false, default: 1
  t.text :file_data                   # Shrine attachment data (jsonb-like text)
  t.string :content_type
  t.bigint :file_size
  t.jsonb :provenance, default: {}    # { source: "upload"|"workflow", ... }
  t.bigint :uploaded_by_id, null: false
  t.timestamps
end
add_index :asset_versions, %i[asset_id version], unique: true
add_foreign_key :asset_versions, :users, column: :uploaded_by_id
```

### Upload Flow (Create Action)

```ruby
def create
  asset = find_or_initialize_asset
  version = asset.versions.build(version_params)
  version.version = (asset.versions.maximum(:version) || 0) + 1
  version.uploaded_by = current_user

  ActiveRecord::Base.transaction do
    asset.save!
    version.save!
  end

  respond_with asset, serializer: AssetSerializer
end

def find_or_initialize_asset
  scope.assets.find_or_initialize_by(name: params[:asset][:name]) do |a|
    a.created_by = current_user
    a.asset_type = params[:asset][:asset_type] || "document"
  end
end
```

### Project Structure Notes

All new files follow existing project structure:
- `web/app/models/asset.rb`
- `web/app/models/asset_version.rb`
- `web/app/uploaders/asset_file_uploader.rb`
- `web/app/controllers/api/v1/company/assets_controller.rb`
- `web/app/controllers/api/v1/company/projects/assets_controller.rb`
- `web/app/serializers/api/v1/asset_serializer.rb`
- `web/app/policies/api/v1/company/assets_policy.rb`
- `web/app/policies/api/v1/company/projects/assets_policy.rb`
- `web/db/migrate/TIMESTAMP_create_assets.rb`
- `web/db/migrate/TIMESTAMP_create_asset_versions.rb`
- `web/test/models/asset_test.rb`
- `web/test/models/asset_version_test.rb`
- `web/test/factories/assets.rb`
- `web/test/factories/asset_versions.rb`

### References

- [Source: ai/workflow-architecture.md#2.8] — Original Asset model design (adapted: polymorphic scope instead of belongs_to :project, AssetVersion instead of self-referential parent)
- [Source: ai/epics/epic-10-artifacts-phase-6.md#Story 10.1] — Epic acceptance criteria
- [Source: web/app/models/skill.rb] — Polymorphic scope pattern reference
- [Source: web/app/uploaders/logo_uploader.rb] — Shrine uploader pattern
- [Source: web/config/initializers/shrine.rb] — Shrine S3/FileSystem/Memory config
- [Source: web/config/routes.rb] — Route namespace structure

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus (Cursor)

### Debug Log References

- Shrine `Attacher.validate` requires `plugin :validation_helpers` (not loaded by default)
- Polymorphic `belongs_to :scope` tries to constantize scope_type during validation — cannot test invalid scope_type values directly
- AssetVersion `set_version` callback always auto-computes; DB default `version: 1` conflicts with auto-increment — removed guard clause, version is always auto-computed
- Company destroy cascade: users FK on assets.created_by_id requires assets to be destroyed before users

### Completion Notes List

- All 8 tasks completed, 34 model tests passing (23 Asset + 11 AssetVersion)
- Full test suite: 882 tests, 0 new failures (4 pre-existing failures in UnifiedContainerWorkflowTest — unrelated)
- Asset model follows Skill polymorphic scope pattern exactly
- AssetVersion with Shrine attachment and auto-incrementing version
- Company and project controllers with find-or-create versioning logic
- Ransack integration for filtering

### File List

- web/db/migrate/20260218100000_create_assets.rb (new)
- web/db/migrate/20260218100001_create_asset_versions.rb (new)
- web/app/models/asset.rb (new)
- web/app/models/asset_version.rb (new)
- web/app/models/company.rb (modified — added has_many :assets)
- web/app/models/project.rb (modified — added has_many :assets)
- web/app/uploaders/asset_file_uploader.rb (new)
- web/app/controllers/api/v1/company/assets_controller.rb (new)
- web/app/controllers/api/v1/company/projects/assets_controller.rb (new)
- web/app/serializers/api/v1/asset_serializer.rb (new)
- web/app/policies/api/v1/company/assets_policy.rb (new)
- web/app/policies/api/v1/company/projects/assets_policy.rb (new)
- web/config/routes.rb (modified — added assets routes)
- web/test/models/asset_test.rb (new)
- web/test/models/asset_version_test.rb (new)
- web/test/factories/assets.rb (new)
- web/test/factories/asset_versions.rb (new)
- ai/sprint-status.yaml (modified — status updates)
- ai/workflow-architecture.md (modified — updated Asset section 2.8)
