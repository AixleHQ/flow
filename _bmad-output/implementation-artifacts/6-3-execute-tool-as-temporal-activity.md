# Story 6.3: Execute Tool as Temporal Activity

Status: review

## Story

As a system,
I want to execute custom tools as Temporal Activities,
so that tool execution is reliable, trackable, and can be retried on failure.

## Acceptance Criteria

1. ✅ Temporal Activity pulls Docker image specified in tool definition
2. ✅ Creates container with injected config items as environment variables
3. ✅ Mounts tool files into container at `/workspace/`
4. ✅ Executes tool command with provided parameters
5. ✅ Captures exit code, stdout, stderr
6. ✅ Cleans up container after execution (success or failure)
7. ✅ Returns structured result: `{exit_code, stdout, stderr, duration_ms}`
8. ✅ Activity can be retried on transient failures

## Tasks / Subtasks

- [x] Task 1: PullDockerImageActivity (AC: 1)
  - [x] Check if image exists locally
  - [x] Pull image if not cached
  - [x] Handle timeout and errors

- [x] Task 2: ToolExecutionService (AC: 2-7)
  - [x] Resolve config items (company/project override)
  - [x] Prepare tool files in temp directory
  - [x] Create Docker container with env vars and volume mount
  - [x] Execute with timeout (default 5min, max 30min)
  - [x] Capture stdout/stderr with proper parsing
  - [x] Cleanup container and temp files
  - [x] Resource limits (512MB RAM, 50% CPU)

- [x] Task 3: ExecuteToolActivity (AC: 2-7)
  - [x] Thin wrapper around ToolExecutionService
  - [x] Error handling with retryable/non-retryable classification

- [x] Task 4: ToolExecutionWorkflow (AC: 8)
  - [x] Orchestrates pull + execute activities
  - [x] Configured in workflows.yml
  - [x] Returns structured result

- [x] Task 5: Tests (AC: all)
  - [x] Unit tests for ToolExecutionService

## Dev Notes

### Architecture Simplification

Per user feedback, simplified approach:
- **No ToolExecution model** — tools return results directly, no persistent tracking
- **Workflow for MCP** — will be called synchronously from MCP server in future stories
- **Simple result** — `{exit_code, stdout, stderr, duration_ms}`

### Workflow Design

```ruby
# Input
{ tool_id:, parameters: {}, project_id: nil, timeout: 300 }

# Output
{ exit_code:, stdout:, stderr:, duration_ms: }
```

### Security Measures

- Timeout enforcement (max 30 minutes) — prevents crypto mining
- Resource limits (512MB RAM, 50% CPU)
- Container auto-cleanup
- Output truncation (max 1MB)

### Config Item Resolution

```ruby
# Resolution order (project overrides company):
# 1. Check project-level config items
# 2. Fall back to company-level config items
```

### References

- [Source: ai/epics.md#Story 6.3]
- [Source: web/app/services/container_service.rb] - Docker patterns

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4

### Completion Notes List

- Simplified to workflow-only approach (no ToolExecution model)
- Will be used by MCP servers to give agents tool capabilities
- All 272 tests pass

### File List

- `web/app/services/tool_execution_service.rb` (new)
- `web/app/temporal/activities/pull_docker_image_activity.rb` (new)
- `web/app/temporal/activities/execute_tool_activity.rb` (new)
- `web/app/temporal/workflows/tool_execution_workflow.rb` (new)
- `web/app/temporal/workflows.yml` (modified)
- `web/test/services/tool_execution_service_test.rb` (new)
