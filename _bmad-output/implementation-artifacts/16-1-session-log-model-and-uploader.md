# Story 16.1: SessionLog Model & Uploader

Status: ready-for-dev

## Story

As a platform engineer,
I want session logs stored as real files with Shrine,
so that logs aren't truncated in metadata JSON and can be downloaded/analyzed later.

## Acceptance Criteria

1. **AC1: Migration** — New table `session_logs` with columns: `id` (bigint PK), `terminal_session_id` (bigint, not null, FK, index), `name` (string, not null), `file_data` (text — Shrine), `file_size` (bigint), `content_type` (string), `created_at`, `updated_at`.

2. **AC2: Model** — `SessionLog` model with `belongs_to :terminal_session`. Validates: `name` presence, `terminal_session` presence.

3. **AC3: Uploader** — `SessionLogUploader < Shrine` with plugins: `activerecord`, `determine_mime_type`, `pretty_location`, `validation_helpers`. Max size 1 GB. Custom `generate_location` producing `sessions/{session_id}/logs/{filename}`.

4. **AC4: Relation** — `TerminalSession has_many :session_logs, dependent: :destroy`.

5. **AC5: Serializer** — `SessionLogSerializer` with attributes: `id`, `name`, `file_size`, `content_type`, `download_url`, `created_at`.

## Tasks / Subtasks

- [ ] Task 1: Create migration (AC: #1)
  - [ ] 1.1 Generate migration `CreateSessionLogs`
  - [ ] 1.2 Add `terminal_session_id` FK with `on_delete: :cascade`
  - [ ] 1.3 Add index on `terminal_session_id`
  - [ ] 1.4 Run migration, verify schema.rb
- [ ] Task 2: Create SessionLogUploader (AC: #3)
  - [ ] 2.1 Create `web/app/uploaders/session_log_uploader.rb`
  - [ ] 2.2 Add plugins: `activerecord`, `determine_mime_type`, `pretty_location`, `restore_cached_data`, `cached_attachment_data`, `validation_helpers`
  - [ ] 2.3 Add `validate_max_size 1024 * 1024 * 1024`
  - [ ] 2.4 Override `generate_location` for path `sessions/{session_id}/logs/{filename}`
- [ ] Task 3: Create SessionLog model (AC: #2)
  - [ ] 3.1 Create `web/app/models/session_log.rb`
  - [ ] 3.2 Add `belongs_to :terminal_session`
  - [ ] 3.3 Include `SessionLogUploader::Attachment(:file)`
  - [ ] 3.4 Add validations: `name` presence, `terminal_session` presence
- [ ] Task 4: Add relation on TerminalSession (AC: #4)
  - [ ] 4.1 Add `has_many :session_logs, dependent: :destroy` to `TerminalSession`
- [ ] Task 5: Create SessionLogSerializer (AC: #5)
  - [ ] 5.1 Create `web/app/serializers/session_log_serializer.rb`
  - [ ] 5.2 Attributes: `id`, `name`, `file_size`, `content_type`, `download_url`, `created_at`
  - [ ] 5.3 `download_url` method returns `object.file_url` with content disposition
- [ ] Task 6: Write tests
  - [ ] 6.1 Model test: validations, associations
  - [ ] 6.2 Factory: `session_log` factory with file attachment

## Dev Notes

### Migration Pattern

Follow existing migration patterns. The latest migration version is `2026_02_19_220000`. Use next timestamp.

```ruby
class CreateSessionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :session_logs do |t|
      t.references :terminal_session, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false
      t.text :file_data
      t.bigint :file_size
      t.string :content_type
      t.timestamps
    end
  end
end
```

### Uploader — Follow AssetFileUploader Pattern

The existing `AssetFileUploader` (at `web/app/uploaders/asset_file_uploader.rb`) is the model to follow:

```ruby
class SessionLogUploader < Shrine
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
    return super unless record.is_a?(SessionLog)

    session_id = record.terminal_session_id
    filename = super(io).split("/").last

    "sessions/#{session_id}/logs/#{filename}"
  end
end
```

### Model

```ruby
class SessionLog < ApplicationRecord
  include SessionLogUploader::Attachment(:file)

  belongs_to :terminal_session

  validates :name, presence: true
  validates :terminal_session, presence: true
end
```

### Serializer — Follow Existing Pattern

Application uses `ApplicationSerializer` base class (inherits from `ActiveModel::Serializer` or similar). Follow `AssetVersionSerializer` pattern.

```ruby
class SessionLogSerializer < ApplicationSerializer
  attributes :id, :name, :file_size, :content_type, :download_url, :created_at

  def download_url
    return nil unless object.file.present?

    object.file_url(
      response_content_disposition: ::ContentDisposition.attachment(object.name)
    )
  end
end
```

### Shrine Storage Configuration

Shrine is already configured in `web/config/initializers/shrine.rb`:
- Development: `FileSystem` storage at `public/cache` and `public/store`
- Test: `Memory` storage
- Production: S3 with `Settings.aws.*`

No changes needed — `SessionLogUploader` inherits global storage configuration.

### Files to Touch

- `web/db/migrate/YYYYMMDD_create_session_logs.rb` (new)
- `web/app/uploaders/session_log_uploader.rb` (new)
- `web/app/models/session_log.rb` (new)
- `web/app/models/terminal_session.rb` — add `has_many :session_logs`
- `web/app/serializers/session_log_serializer.rb` (new)
- `web/test/models/session_log_test.rb` (new)
- `web/test/factories/session_logs.rb` (new)

### What NOT To Change

- Do NOT modify `before_cleanup` — that's Story 16.2
- Do NOT modify `TerminalSessionSerializer` — that's Story 16.7
- Do NOT create API endpoints for logs — they'll be consumed via session serializer

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.1]
- [Source: web/app/uploaders/asset_file_uploader.rb — uploader pattern]
- [Source: web/app/models/asset_version.rb — Shrine attachment include pattern]
- [Source: web/config/initializers/shrine.rb — storage configuration]
- [Source: web/db/schema.rb — existing table patterns and FK constraints]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
