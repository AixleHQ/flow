# Story 17.7: Remove Unified Container Workflow

Status: review

## Story

As a platform engineer,
I want the old `UnifiedContainerWorkflow` and associated routing code deleted,
so that there is no dead code or confusion about which workflow runs containers.

## Acceptance Criteria

1. **AC1: Workflow deletion** — `web/app/temporal/workflows/unified_container_workflow.rb` deleted after all callers migrated.

2. **AC2: Old activities deletion** — `execute_container_activity.rb`, `pull_docker_image_activity.rb`, `cleanup_container_activity.rb` deleted. These are the old activities that used `ContainerActivityBase` for routing.

3. **AC3: ContainerActivityBase cleanup** — Either deleted entirely (if no shared utility methods remain) or stripped to a minimal error-wrapping concern.

4. **AC4: No dangling references** — No file in the project references `UnifiedContainerWorkflow`, `ExecuteContainerActivity` (old), `PullDockerImageActivity` (old), or `CleanupContainerActivity` (old). Grep confirms zero hits.

5. **AC5: Tests cleanup** — All tests for removed classes are deleted. New tests cover the replacement classes (from 17.2, 17.3, 17.5).

6. **AC6: Temporal registration** — Old workflow and activities deregistered from Temporal worker config.

## Tasks / Subtasks

- [x] Task 1: Verify all callers migrated (AC: #4)
  - [x] 1.1 Grep for UnifiedContainerWorkflow references
  - [x] 1.2 Grep for old activity class references
  - [x] 1.3 Verify ContainerWorkflowService only dispatches to new workflows
- [x] Task 2: Delete old workflow (AC: #1)
  - [x] 2.1 Delete unified_container_workflow.rb
- [x] Task 3: Delete old activities (AC: #2)
  - [x] 3.1 Delete execute_container_activity.rb
  - [x] 3.2 Delete pull_docker_image_activity.rb
  - [x] 3.3 Delete cleanup_container_activity.rb
- [x] Task 4: Clean up ContainerActivityBase (AC: #3)
  - [x] 4.1 If useful methods remain, extract to concern
  - [x] 4.2 Delete base file if empty
- [x] Task 5: Clean up tests (AC: #5)
  - [x] 5.1 Delete old workflow tests
  - [x] 5.2 Delete old activity tests
  - [x] 5.3 Verify new tests pass
- [x] Task 6: Update Temporal registration (AC: #6)
  - [x] 6.1 Remove old classes from worker config
  - [x] 6.2 Verify only new workflows/activities registered

## Dev Notes

### Files to delete

- `web/app/temporal/workflows/unified_container_workflow.rb`
- `web/app/temporal/activities/execute_container_activity.rb`
- `web/app/temporal/activities/pull_docker_image_activity.rb`
- `web/app/temporal/activities/cleanup_container_activity.rb`
- `web/app/temporal/activities/container_activity_base.rb` (if fully replaced)
- `web/test/temporal/workflows/unified_container_workflow_test.rb` (if exists)
- `web/test/temporal/activities/execute_container_activity_test.rb` (if exists)

### Safety

This is the LAST story in the workflow migration sequence. Only execute after:
- 17.2 (AgentContainerWorkflow) — tested and deployed
- 17.3 (ToolExecutionWorkflow) — tested and deployed
- 17.5 (Thin activities) — tested and deployed
- 17.6 (Workflow initiation) — all callers migrated

### Running Temporal workflows

If there are still-running workflows of the old type, they must complete before unregistering. Check Temporal UI for active `unified_container_workflow` executions.

### Verification checklist

```bash
# After deletion, all should return 0 results:
rg "UnifiedContainerWorkflow" web/
rg "ExecuteContainerActivity" web/  # old one
rg "PullDockerImageActivity" web/   # old one
rg "CleanupContainerActivity" web/  # old one
rg "ContainerActivityBase" web/     # if deleted
```

### References

- [Source: web/app/temporal/workflows/unified_container_workflow.rb](web/app/temporal/workflows/unified_container_workflow.rb) — to be deleted
- [Source: web/app/temporal/activities/container_activity_base.rb](web/app/temporal/activities/container_activity_base.rb) — to be deleted
