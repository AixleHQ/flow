# Story 16.4: Collect Outputs as Pending Assets

Status: ready-for-dev

## Story

As a platform engineer,
I want files from `/workspace/outputs/` to be collected as Asset records with `pending_review` status,
so that users can decide which session outputs to keep as permanent project assets.

## Acceptance Criteria

1. **AC1: Assets migration** — Alter `assets` table: add `terminal_session_id` (bigint, nullable, FK → terminal_sessions, index), `status` (string, not null, default `"active"`, index), `reviewed_at` (datetime, nullable).

2. **AC2: Terminal sessions migration** — Add `artifacts_reviewed` (boolean, default `false`) column to `terminal_sessions`.

3. **AC3: Asset model changes** — Add `belongs_to :terminal_session, optional: true`. Add `status` validation (inclusion: `active`, `pending_review`, `dismissed`). Add scopes: `pending_review`, `dismissed`. Update existing `active` scope to include `status: "active"` condition.

4. **AC4: AssetVersion source** — Add `:session` to `enumerize :source` in `AssetVersion`.

5. **AC5: TerminalSession relation** — `has_many :output_assets, class_name: "Asset", foreign_key: :terminal_session_id`.

6. **AC6: collect_outputs method** — Replace the stub from Story 16.2 with full implementation. Lists files in `/workspace/outputs/`, creates Asset + AssetVersion records per file with `status: "pending_review"`.

7. **AC7: Scope resolution** — If session has a project, scope to Project; otherwise scope to user's Company.

## Tasks / Subtasks

- [ ] Task 1: Create assets migration (AC: #1)
  - [ ] 1.1 Add `terminal_session_id` bigint nullable with FK (on_delete: :nullify)
  - [ ] 1.2 Add `status` string not null default "active" with index
  - [ ] 1.3 Add `reviewed_at` datetime nullable
  - [ ] 1.4 Backfill: `UPDATE assets SET status = 'active' WHERE status IS NULL` (if needed)
- [ ] Task 2: Create terminal_sessions migration (AC: #2)
  - [ ] 2.1 Add `artifacts_reviewed` boolean default false
- [ ] Task 3: Update Asset model (AC: #3)
  - [ ] 3.1 Add `belongs_to :terminal_session, optional: true`
  - [ ] 3.2 Add `validates :status, presence: true, inclusion: { in: %w[active pending_review dismissed] }`
  - [ ] 3.3 Add `scope :pending_review, -> { where(status: "pending_review") }`
  - [ ] 3.4 Add `scope :dismissed, -> { where(status: "dismissed") }`
  - [ ] 3.5 Update `scope :active` to include `.where(status: "active")` condition
  - [ ] 3.6 Update `ransackable_attributes` to include `status`, `terminal_session_id`
- [ ] Task 4: Update AssetVersion source enum (AC: #4)
  - [ ] 4.1 Add `:session` to `enumerize :source, in: %i[upload workflow github session]`
- [ ] Task 5: Add TerminalSession relation (AC: #5)
  - [ ] 5.1 Add `has_many :output_assets, class_name: "Asset", foreign_key: :terminal_session_id`
- [ ] Task 6: Implement collect_outputs (AC: #6, #7)
  - [ ] 6.1 Replace stub in `agent_session_strategy.rb`
  - [ ] 6.2 List files via `runtime.exec(container, ["find", "/workspace/outputs", "-maxdepth", "1", "-type", "f"])`
  - [ ] 6.3 For each file: read content, determine scope, create Asset + AssetVersion
  - [ ] 6.4 Use `Tempfile` for large files to avoid memory pressure
  - [ ] 6.5 Handle errors per-file (skip and continue)
  - [ ] 6.6 Return count of collected outputs
- [ ] Task 7: Write tests
  - [ ] 7.1 Asset model: test new validations, scopes, association
  - [ ] 7.2 Integration: test collect_outputs creates assets with correct status

## Dev Notes

### Migration — Assets

```ruby
class AddSessionOutputFieldsToAssets < ActiveRecord::Migration[8.1]
  def change
    add_reference :assets, :terminal_session, null: true,
                  foreign_key: { on_delete: :nullify }, index: true
    add_column :assets, :status, :string, null: false, default: "active"
    add_column :assets, :reviewed_at, :datetime
    add_index :assets, :status
  end
end
```

Using `on_delete: :nullify` — if a session is deleted, assets persist but lose session reference. This is correct: assets may have been "saved" (active status) and should not be cascade-deleted.

### Migration — Terminal Sessions

```ruby
class AddArtifactsReviewedToTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :terminal_sessions, :artifacts_reviewed, :boolean, default: false
  end
end
```

### Asset Model Changes

Current `active` scope:
```ruby
scope :active, -> { where(deleted_at: nil) }
```

Updated:
```ruby
scope :active, -> { where(deleted_at: nil, status: "active") }
```

This is a **breaking change** for existing queries that expect `active` to return all non-deleted assets. Review all callers:
- `Asset.for_company(company)` already chains `.active` via `where(deleted_at: nil)` — now also needs `status: "active"`
- Since all existing assets will get `status: "active"` from the default, this is safe

### collect_outputs Implementation

```ruby
def collect_outputs(container, session)
  output_dir = "/workspace/outputs"

  result = runtime.exec(
    container,
    ["/bin/sh", "-c", "find #{output_dir} -maxdepth 1 -type f 2>/dev/null || true"],
    stdout: true, stderr: true
  )
  return 0 unless result[2].zero?

  files = result[0].join.split("\n").reject(&:blank?)
  return 0 if files.empty?

  scope_type, scope_id = resolve_output_scope(session)
  count = 0

  files.each do |file_path|
    filename = File.basename(file_path)
    content = read_file_from_container(container, file_path)
    next if content.blank?

    io = Tempfile.new(["output-", File.extname(filename)])
    io.binmode
    io.write(content)
    io.rewind
    io.define_singleton_method(:original_filename) { filename }

    asset = Asset.create!(
      name: filename,
      folder: "session-#{session.id}",
      scope_type: scope_type,
      scope_id: scope_id,
      created_by: session.user,
      terminal_session: session,
      status: "pending_review"
    )

    AssetVersion.create!(
      asset: asset,
      uploaded_by: session.user,
      source: :session,
      file: io
    )

    count += 1
    Rails.logger.info("[AgentSession] Collected output: #{filename}")
  rescue StandardError => e
    Rails.logger.warn("[AgentSession] Failed to collect output #{file_path}: #{e.message}")
  ensure
    io&.close!
  end

  count
end

def resolve_output_scope(session)
  if session.project.present?
    ["Project", session.project_id]
  else
    ["Company", session.user.company_id]
  end
end
```

### Uniqueness Constraint Impact

Assets have a unique index on `(scope_type, scope_id, folder, name)`. Using `folder: "session-#{session.id}"` ensures uniqueness per session — no collision with existing assets.

### Large Files Strategy

Use `Tempfile` instead of `StringIO` for output files to handle large files without memory pressure. `Tempfile` is automatically cleaned up in `ensure` block.

### Asset Folder Convention

Session outputs are placed in folder `session-{id}` to group them and avoid naming conflicts with user-uploaded assets.

### Files to Touch

- `web/db/migrate/YYYYMMDD_add_session_output_fields_to_assets.rb` (new)
- `web/db/migrate/YYYYMMDD_add_artifacts_reviewed_to_terminal_sessions.rb` (new)
- `web/app/models/asset.rb` — new association, scopes, validations
- `web/app/models/asset_version.rb` — add `:session` to source enum
- `web/app/models/terminal_session.rb` — add `has_many :output_assets`
- `web/app/services/container_strategies/agent_session_strategy.rb` — implement `collect_outputs`, add `resolve_output_scope`
- `web/test/models/asset_test.rb` — test new fields
- `web/test/services/container_strategies/agent_session_strategy_test.rb` — test collect_outputs

### Dependencies

- **Requires Story 16.2** — `collect_outputs` stub already in place
- **Requires Story 16.3** — Output directory renamed to `/workspace/outputs/`

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.4]
- [Source: web/app/models/asset.rb — current model and scopes]
- [Source: web/app/models/asset_version.rb — source enumerize]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — collect_outputs stub]
- [Source: web/db/schema.rb — assets table and index definitions]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
