# Story 31.1: Workflow Base Resources API

Status: done

## Story

As a workflow designer,
I want to configure base tools, skills, MCP servers, and assets on a workflow via the API,
so that these resources are available in all steps without per-step duplication.

## Acceptance Criteria

1. **Save base tool IDs** — Given a PATCH request to workflow with `config: { base_tool_ids: [1, 2] }`, when the workflow is saved, then `workflow.base_tool_ids` returns `[1, 2]`

2. **Save base skill IDs** — Same pattern for `config.base_skill_ids`

3. **Save base MCP server IDs** — Same pattern for `config.base_mcp_server_ids`

4. **Save base asset IDs** — Same pattern for `config.base_asset_ids`

5. **Save inherit_all flag** — Given a workflow update with `config: { inherit_all_project_resources: true }`, when saved, then `workflow.inherit_all_project_resources` returns `true`

6. **Safe defaults** — Given a workflow with no config set, when `workflow.base_tool_ids` is called, then returns `[]` (safe default). Same for all base resource methods

7. **Serialization** — Given a workflow API response, when serialized, then response includes `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids`, `base_asset_ids`, `inherit_all_project_resources` as top-level attributes (not nested in config)

8. **Strong params** — WorkflowsController permits `config` nested params including base resource arrays and inherit_all flag

## Tasks / Subtasks

- [x] Task 1: Verify Workflow model helper methods (AC: #1-#6)
  - [x] Readers already exist from Epic 29
  - [x] Added `merge_config!` method for partial updates
  - [x] Safe defaults confirmed ([] / false)
- [x] Task 2: Update WorkflowSerializer (AC: #7)
  - [x] Added `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids`, `base_asset_ids`, `inherit_all_project_resources` as attributes
- [x] Task 3: Fix WorkflowsController for partial config merge (AC: #8)
  - [x] `config: {}` permits arbitrary keys
  - [x] Fixed update action to merge config into existing config instead of replacing
- [x] Task 4: merge_config! convenience method on Workflow (AC: #1-#5)
  - [x] Merges into existing config JSONB without overwriting other keys
- [x] Task 5: Write backend tests (AC: #1-#8)
  - [x] 9 tests: defaults, round-trip, merge without overwrite, inherit_all

## Dev Notes

### Architecture Patterns

- **JSONB config** — Workflow uses `config` JSONB column for flexible configuration. Base resource IDs are stored as arrays within this column. No new database columns needed
- **Strong params with JSONB** — Rails `permit(config: {})` allows any nested hash. Since `config` is JSONB, the controller already accepts arbitrary keys. Verify this works with array values
- **ActiveModelSerializers** — Project uses AMS. Add attributes to WorkflowSerializer that delegate to model methods

### Existing Code Context

- **Workflow model** (`app/models/workflow.rb`) — Already has `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids`, `base_asset_ids`, `inherit_all_project_resources` reader methods from Epic 29. Missing setter methods
- **WorkflowSerializer** (`app/serializers/workflow_serializer.rb`) — Currently exposes `config` as raw JSONB. Needs explicit attributes for base resource fields
- **WorkflowsController** (`app/controllers/api/v1/company/projects/workflows_controller.rb`) — `workflow_params` permits `:name, :description, config: {}`. The `config: {}` pattern should allow nested keys

### Important: Partial JSONB Update

When updating `config` via API, ensure partial updates work correctly:
```ruby
# BAD: This replaces entire config
workflow.update(config: { base_tool_ids: [1, 2] })  # Erases base_skill_ids!

# GOOD: Merge into existing config
workflow.config = (workflow.config || {}).merge(params[:config])
workflow.save!
```

The controller must handle this — either in `workflow_params` processing or via model callback. **Check current behavior and fix if it does full replacement.**

### File Locations

- Modified: `app/models/workflow.rb` — add setter methods
- Modified: `app/serializers/workflow_serializer.rb` — add base resource attributes
- Possibly modified: `app/controllers/api/v1/company/projects/workflows_controller.rb` — verify/fix config merge behavior
- New/Modified: `test/models/workflow_test.rb` — config getter/setter tests
- New/Modified: `test/controllers/api/v1/company/projects/workflows_controller_test.rb` — API round-trip tests

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Run:** `docker exec app-web-1 bundle exec rails test test/models/workflow_test.rb`
- Test JSONB merge behavior to prevent data loss on partial updates

### Previous Story Intelligence

- Epic 29 (especially 29.3) added the reader methods on Workflow for base resources and inherit_all. This story completes the cycle with setters, serialization, and API round-trip
- `SessionConfigResolver` already consumes these fields — this story ensures they can be populated via the API

### References

- [Source: ai/epics/epic-31-workflow-base-resources-ui.md#Story 31.1] — AC and technical notes
- [Source: ai/session-config-cascade.md#6.2] — Workflow base resources design
- [Source: app/models/workflow.rb] — Current Workflow model with reader methods
- [Source: app/serializers/workflow_serializer.rb] — Current serializer
- [Source: app/controllers/api/v1/company/projects/workflows_controller.rb] — Current controller
- [Source: _bmad-output/implementation-artifacts/29-3-workflow-inherit-all-project-resources-flag.md] — Previous reader implementation

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- Fixed critical issue: controller was replacing entire config JSONB on update. Now merges.
- Added merge_config! for programmatic partial updates
- 9 tests, 14 assertions, 0 failures

### File List

- app/models/workflow.rb (modified — added merge_config!)
- app/serializers/workflow_serializer.rb (modified — added base resource attributes)
- app/controllers/api/v1/company/projects/workflows_controller.rb (modified — config merge in update)
- test/models/workflow_config_test.rb (new)
