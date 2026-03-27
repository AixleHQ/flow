# Story 19.3: ToolResult Serializer

Status: ready-for-dev

## Story

As a system,
I want to serialize ToolResult for agent consumption with presigned download URLs,
so that agents receive compact metadata and download large files via curl.

## Acceptance Criteria

1. `ToolResultSerializer < ApplicationSerializer` created
2. Attributes: `execution_id`, `tool_name`, `state`, `exit_code`, `error`, `duration_ms`, `created_at`
3. For each attachment (stdout, stderr, result_data, output): `{name}_url` (presigned, 1h TTL) and `{name}_size`
4. Nil attachments produce nil URL/size attributes
5. Presigned URLs use `expires_in: 3600`
6. Total serialized payload ~200-400 bytes for typical result

## Tasks / Subtasks

- [ ] Task 1: Serializer (AC: #1-#5)
  - [ ] Create `app/serializers/tool_result_serializer.rb`
  - [ ] `URL_TTL = 3600` constant
  - [ ] Standard attributes: execution_id, state, exit_code, error, duration_ms, created_at
  - [ ] Computed `tool_name` from `object.tool.name`
  - [ ] For each of 4 attachments: `{name}_url` and `{name}_size` computed attributes
  - [ ] Use `object.{name}&.url(expires_in: URL_TTL)` for URLs
  - [ ] Use `object.{name}&.metadata&.dig("size")` for sizes
- [ ] Task 2: Tests (AC: #4, #6)
  - [ ] Test serialization with all attachments present
  - [ ] Test serialization with nil attachments → nil URLs
  - [ ] Test serialization of processing state (no attachments yet)
  - [ ] Verify payload size is compact

## Dev Notes

- Follow `ApplicationSerializer` base class pattern (ActiveModel::Serializer)
- `url(expires_in:)` works for S3 storage (presigned). For FileSystem storage (dev), it returns regular URL — that's fine
- Verify presigned URLs are accessible from inside agent containers (minio hostname resolution)

### Project Structure Notes

- `app/serializers/tool_result_serializer.rb` — new file

### References

- [Source: ai/tool-execution-framework.md#4] — serializer code
- [Source: app/serializers/tool_serializer.rb] — existing serializer pattern
- [Source: config/initializers/shrine.rb] — URL options, presigned config
