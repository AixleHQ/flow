# Story 19.2: ToolResult Model + Uploader

Status: ready-for-dev

## Story

As a system,
I want to persist container tool execution results in a dedicated model with Shrine attachments,
so that results are stored in S3 (not Temporal payloads) and delivered via presigned URLs.

## Acceptance Criteria

1. Migration creates `tool_results` table with: `execution_id` (string, unique index, not null), `state` (string, default "processing", not null), `tool_id` (references, not null), `terminal_session_id` (references, optional), `step_run_id` (references, optional), `exit_code` (integer), `error` (string), `duration_ms` (integer), and 4 Shrine columns: `stdout_data`, `stderr_data`, `result_data_data`, `output_data` (all text)
2. `ToolResult` model has 4 Shrine attachments: `stdout`, `stderr`, `result_data`, `output`
3. `ToolResult.generate_id` returns `"tr-#{SecureRandom.hex(12)}"`
4. `complete!` method: sets state (completed/failed), uploads non-empty strings as Shrine attachments, auto-parses JSON stdout into `result_data`, sets error field
5. `attach_output_files(container, paths, runtime)` reads files from container, packs tar.gz, attaches as `output`
6. States validated: `processing`, `completed`, `failed`, `expired`
7. Scope `stale(age)` returns completed/failed records older than given age
8. Nil attachments left as nil (no empty uploads)

## Tasks / Subtasks

- [ ] Task 1: ToolResultUploader (AC: #2)
  - [ ] Create `app/uploaders/tool_result_uploader.rb`
  - [ ] Plugins: activerecord, determine_mime_type, pretty_location, restore_cached_data, cached_attachment_data
  - [ ] Custom `generate_location`: `tool_results/{execution_id}/{name}/{filename}`
- [ ] Task 2: Migration (AC: #1)
  - [ ] Create `tool_results` table with all columns
  - [ ] Index on `execution_id` (unique)
  - [ ] Foreign keys on tool_id, terminal_session_id, step_run_id
- [ ] Task 3: ToolResult model (AC: #2-#8)
  - [ ] 4 Shrine attachment includes
  - [ ] Associations: belongs_to tool, optional terminal_session, optional step_run
  - [ ] Validations: execution_id presence + uniqueness, state inclusion
  - [ ] `generate_id` class method
  - [ ] `complete!` instance method — state transition, upload attachments, JSON parsing
  - [ ] `attach_output_files` — collect from container, pack, upload
  - [ ] Private: `string_to_io`, `try_parse_json`, `read_file_from_container`
  - [ ] Scope: `stale`
- [ ] Task 4: TarGzPacker utility (AC: #5)
  - [ ] Create `app/services/tar_gz_packer.rb`
  - [ ] `.pack(files_hash)` → tar.gz binary string
  - [ ] Uses `Gem::Package::TarWriter` + `Zlib::GzipWriter`
- [ ] Task 5: Tests
  - [ ] Test `generate_id` format
  - [ ] Test `complete!` with exit_code 0 → completed
  - [ ] Test `complete!` with exit_code != 0 → failed
  - [ ] Test `complete!` with error message → failed
  - [ ] Test `complete!` with JSON stdout → result_data populated
  - [ ] Test `complete!` with non-JSON stdout → result_data nil
  - [ ] Test `complete!` with empty stdout → stdout attachment nil
  - [ ] Test `stale` scope
  - [ ] Test TarGzPacker

## Dev Notes

- Follow existing Shrine patterns from `AssetFileUploader` and `SessionLogUploader`
- `result_data_data` column name is Shrine convention: `{attachment_name}_data`
- `complete!` must handle the case where stdout is valid JSON but very large — just store as-is, no truncation
- `attach_output_files` is called from strategy's `before_cleanup` phase — container is still running at that point

### Project Structure Notes

- `app/uploaders/tool_result_uploader.rb` — new file
- `app/models/tool_result.rb` — new file
- `app/services/tar_gz_packer.rb` — new file
- `db/migrate/YYYYMMDD_create_tool_results.rb` — new migration

### References

- [Source: ai/tool-execution-framework.md#3] — ToolResult model, schema, uploader
- [Source: app/uploaders/session_log_uploader.rb] — Shrine uploader pattern to follow
- [Source: app/uploaders/asset_file_uploader.rb] — custom generate_location pattern
