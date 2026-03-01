# Story 21.6: Task Assets

Status: review

## Story

As a user,
I want to attach files to tasks,
so that I can share documents, designs, and agent outputs on specific tasks.

## Acceptance Criteria

1. Migration creates `task_assets` table: `id` (bigint PK), `board_task_id` (references board_tasks, not null, FK), `name` (string, not null), `author_id` (references users, not null, FK), `author_type` (string, not null, default: "human"), `tags` (string array, default: []), `file_data` (text — Shrine column), `timestamps`
2. `TaskAsset` model with Shrine uploader (`TaskAssetUploader`)
3. Upload endpoint: `POST /board/tasks/:task_id/assets` (multipart or presigned)
4. Download: presigned URL via serializer
5. List: `GET /board/tasks/:task_id/assets` with optional `tag` filter
6. Delete endpoint: `DELETE /board/tasks/:task_id/assets/:id` — admin or author can delete
7. `TaskAssetSerializer` with `id`, `name`, `file_url`, `file_size`, `content_type`, `tags`, `author_id`, `author_type`, `created_at`, `updated_at`
8. `BoardTask` gains `has_many :task_assets, dependent: :destroy`
9. Update `BoardTaskSerializer#assets_count` to return actual count

## Tasks / Subtasks

- [ ] Task 1: Create TaskAssetUploader (AC: #2)
  - [ ] `app/uploaders/task_asset_uploader.rb`
  - [ ] Follow existing Shrine uploader pattern (same plugins as `AssetFileUploader`)
  - [ ] Storage path: `task_assets/{board_task_id}/{filename}`
  - [ ] Max size: 1 GB (same as other uploaders)
- [ ] Task 2: Create migration (AC: #1)
  - [ ] Generate migration `CreateTaskAssets`
  - [ ] `board_task_id` with FK to board_tasks, not null
  - [ ] `name` (string, not null)
  - [ ] `author_id` with FK to users, not null
  - [ ] `author_type` (string, not null, default: "human")
  - [ ] `tags` (string array, default: [])
  - [ ] `file_data` (text — Shrine JSON column)
  - [ ] Timestamps
  - [ ] Index on `board_task_id`
- [ ] Task 3: Create TaskAsset model (AC: #2, #8)
  - [ ] `app/models/task_asset.rb`
  - [ ] `include TaskAssetUploader::Attachment(:file)`
  - [ ] `belongs_to :board_task`, `belongs_to :author, class_name: "User"`
  - [ ] `enumerize :author_type, in: %i[human agent system], default: :human`
  - [ ] Validates `name` presence
  - [ ] `BoardTask` gains `has_many :task_assets, dependent: :destroy`
  - [ ] Ransack config
- [ ] Task 4: Create TaskAssetSerializer (AC: #7)
  - [ ] `app/serializers/task_asset_serializer.rb`
  - [ ] Attributes: `id`, `name`, `file_url`, `file_size`, `content_type`, `tags`, `author_id`, `author_type`, `created_at`, `updated_at`
  - [ ] `file_url` → `object.file&.url`
  - [ ] `file_size` → `object.file&.metadata&.dig("size")`
  - [ ] `content_type` → `object.file&.metadata&.dig("mime_type")`
- [ ] Task 5: Update BoardTaskSerializer (AC: #9)
  - [ ] `assets_count` → `object.task_assets.count`
- [ ] Task 6: Create Pundit policy (AC: #6)
  - [ ] `app/policies/api/v1/company/projects/board/task/assets_policy.rb`
  - [ ] `index?` → `project_accessible?`
  - [ ] `create?` → `project_accessible?`
  - [ ] `destroy?` → `project_accessible? && (project_admin? || author?)`
- [ ] Task 7: Create controller (AC: #3, #4, #5, #6)
  - [ ] `app/controllers/api/v1/company/projects/board/task/assets_controller.rb`
  - [ ] `index`: list assets for task with optional `tag` filter
  - [ ] `create`: upload file with metadata
  - [ ] `destroy`: delete asset (policy checks author or admin)
  - [ ] Tag filter: `where("? = ANY(tags)", params[:tag])`
  - [ ] Strong params: `params.require(:task_asset).permit(:name, :file, tags: [])`
- [ ] Task 8: Add routes (AC: #3, #5, #6)
  - [ ] Nest under tasks: `resources :assets, controller: "board/task/assets", only: [:index, :create, :destroy]`
- [ ] Task 9: Factory and tests
  - [ ] FactoryBot factory for `task_asset`
  - [ ] Model test: validations, associations
  - [ ] Controller test: upload, list with filter, delete authorization

## Dev Notes

### Architecture Compliance

- Reuses existing **Shrine + S3 infrastructure** — no new storage configuration needed
- Storage path: `task_assets/{board_task_id}/{filename}` — consistent with other uploaders
- `author_type` same as comments: `human` / `agent` / `system`
- In test env, Shrine uses `Shrine::Storage::Memory` — no S3 calls in tests

### Existing Shrine Pattern (from project)

Follow `AssetFileUploader` pattern:
```ruby
class TaskAssetUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  Attacher.validate do
    validate_max_size 1024 * 1024 * 1024, message: "is too large (max is 1 GB)"
  end

  def generate_location(io, record: nil, **)
    return super unless record.is_a?(TaskAsset)

    task_id = record.board_task_id
    filename = super(io).split("/").last
    "task_assets/#{task_id}/#{filename}"
  end
end
```

### Model with Shrine Attachment

```ruby
class TaskAsset < ApplicationRecord
  include TaskAssetUploader::Attachment(:file)

  belongs_to :board_task
  belongs_to :author, class_name: "User"

  enumerize :author_type, in: %i[human agent system], default: :human

  validates :name, presence: true
end
```

### Serializer Pattern (presigned URLs)

```ruby
class TaskAssetSerializer < ApplicationSerializer
  attributes :id, :name, :file_url, :file_size, :content_type,
             :tags, :author_id, :author_type, :created_at, :updated_at

  def file_url
    object.file&.url
  end

  def file_size
    object.file&.metadata&.dig("size")
  end

  def content_type
    object.file&.metadata&.dig("mime_type")
  end
end
```

### Delete Authorization

Delete is allowed for:
- Project admin (project owner)
- Asset author (`author_id == current_user.id`)

```ruby
def destroy?
  project_accessible? && (project_admin? || record.author_id == current_user.id)
end
```

### API Contract

```
GET    /api/v1/company/projects/:project_id/board/tasks/:task_id/assets         → index
POST   /api/v1/company/projects/:project_id/board/tasks/:task_id/assets         → create
DELETE /api/v1/company/projects/:project_id/board/tasks/:task_id/assets/:id      → destroy
```

Index supports query param: `tag`

### Project Structure Notes

- `app/uploaders/task_asset_uploader.rb`
- `app/models/task_asset.rb`
- `app/controllers/api/v1/company/projects/board/task/assets_controller.rb`
- `app/serializers/task_asset_serializer.rb`
- `app/policies/api/v1/company/projects/board/task/assets_policy.rb`
- `test/models/task_asset_test.rb`
- `test/controllers/api/v1/company/projects/board/task/assets_controller_test.rb`
- `test/factories/task_assets.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_task_assets.rb`

### References

- [Source: ai/epics/epic-21-tasks-comments-assets.md#Story 21.6]
- [Source: ai/prd/board-tasks.md#FR24, FR25, FR26, FR27]
- [Source: app/uploaders/asset_file_uploader.rb — existing Shrine uploader pattern]
- [Source: app/serializers/asset_serializer.rb — file_url via Shrine]
- [Source: config/initializers/shrine.rb — storage configuration]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
- Dynamic Pundit authorize fix: `AssetsPolicy#destroy?` changed to `project_accessible?` only (record-level author check in controller) because dynamic authorize passes Symbol array, not actual record, so `record.author_id` fails.

### Completion Notes List
- All ACs implemented: Shrine uploader, CRUD (index/create/destroy), tag filter, presigned URLs
- Follows existing `AssetFileUploader` pattern with `TaskAssetUploader`
- Delete authorization: admin OR author (checked in controller)
- `BoardTaskSerializer#assets_count` wired to actual count
- 10 model tests + 10 controller tests = 20 tests

### File List
- `app/uploaders/task_asset_uploader.rb`
- `db/migrate/20260227100004_create_task_assets.rb`
- `app/models/task_asset.rb`
- `app/models/board_task.rb` (modified: added `has_many :task_assets`)
- `app/serializers/task_asset_serializer.rb`
- `app/serializers/board_task_serializer.rb` (modified: assets_count)
- `app/policies/api/v1/company/projects/board/task/assets_policy.rb`
- `app/controllers/api/v1/company/projects/board/task/assets_controller.rb`
- `config/routes.rb` (modified: added assets routes)
- `test/factories/task_assets.rb`
- `test/models/task_asset_test.rb`
- `test/controllers/api/v1/company/projects/board/task/assets_controller_test.rb`
