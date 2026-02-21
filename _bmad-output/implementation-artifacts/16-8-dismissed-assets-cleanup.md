# Story 16.8: Dismissed Assets Cleanup

Status: ready-for-dev

## Story

As a platform engineer,
I want dismissed assets to be automatically cleaned up after a grace period,
so that storage isn't wasted on unwanted session outputs.

## Acceptance Criteria

1. **AC1: Cleanup activity** — `CleanupDismissedAssetsActivity` finds `Asset.dismissed.where("reviewed_at < ?", 7.days.ago)`. Destroys versions (Shrine deletes files from storage), then destroys asset records.

2. **AC2: Cleanup workflow** — `DismissedAssetCleanupWorkflow` wraps the activity. Same pattern as `StaleSessionCleanupWorkflow`.

3. **AC3: Scheduling** — Runs daily via Temporal scheduled workflow.

4. **AC4: Logging** — Logs count of cleaned assets.

5. **AC5: Safety** — Only cleans assets where `reviewed_at IS NOT NULL` and `status = "dismissed"`. Never touches `pending_review`.

## Tasks / Subtasks

- [ ] Task 1: Create cleanup activity (AC: #1, #4, #5)
  - [ ] 1.1 Create `web/app/temporal/activities/cleanup_dismissed_assets_activity.rb`
  - [ ] 1.2 Query: `Asset.dismissed.where(reviewed_at: ...7.days.ago)`
  - [ ] 1.3 For each: destroy versions first, then destroy asset
  - [ ] 1.4 Log total count and freed storage estimate
- [ ] Task 2: Create cleanup workflow (AC: #2)
  - [ ] 2.1 Create `web/app/temporal/workflows/dismissed_asset_cleanup_workflow.rb`
  - [ ] 2.2 Follow `StaleSessionCleanupWorkflow` pattern
- [ ] Task 3: Register workflow and schedule (AC: #3)
  - [ ] 3.1 Register in workflow service configuration
  - [ ] 3.2 Add to Temporal schedules (daily, 3 AM UTC or similar)
- [ ] Task 4: Write tests
  - [ ] 4.1 Activity test: cleans old dismissed, leaves recent dismissed
  - [ ] 4.2 Activity test: never touches pending_review
  - [ ] 4.3 Activity test: Shrine files deleted from storage

## Dev Notes

### Activity Pattern — Follow StaleSessionCleanupActivity

```ruby
module Activities
  class CleanupDismissedAssetsActivity < ApplicationActivity
    GRACE_PERIOD = 7.days

    def run(_input = nil)
      assets = Asset.dismissed
                    .where.not(reviewed_at: nil)
                    .where(reviewed_at: ...GRACE_PERIOD.ago)

      count = 0
      freed_bytes = 0

      assets.find_each do |asset|
        bytes = asset.versions.sum(:file_size).to_i
        asset.versions.each(&:destroy!)
        asset.destroy!
        count += 1
        freed_bytes += bytes
        log(:info, "Cleaned dismissed asset #{asset.id}: #{asset.name}")
      rescue StandardError => e
        log(:warn, "Failed to clean asset #{asset.id}: #{e.message}")
      end

      log(:info, "Cleaned #{count} dismissed assets, freed ~#{freed_bytes / 1024 / 1024} MB")
      { cleaned_count: count, freed_bytes: freed_bytes }
    end
  end
end
```

### Workflow Pattern

```ruby
module Workflows
  class DismissedAssetCleanupWorkflow < Base
    ACTIVITY_TIMEOUT = 600 # 10 minutes (may process many assets)

    def run(_input = nil)
      execute_activity(
        activities.cleanup_dismissed_assets_activity,
        {},
        start_to_close_timeout: ACTIVITY_TIMEOUT,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end

    private

    def activities
      @activities ||= WorkflowService.dismissed_asset_cleanup_workflow.activities
    end
  end
end
```

### Shrine File Deletion

When `AssetVersion` is destroyed and it has a Shrine attachment, Shrine automatically deletes the file from storage (S3/filesystem) via the `activerecord` plugin's `after_destroy` callback. No manual file deletion needed.

### WorkflowService Registration

Check how `StaleSessionCleanupWorkflow` is registered. Look for `WorkflowService` configuration — likely in an initializer or YAML config.

### Temporal Schedule

Follow existing schedule pattern. The schedule config is usually in `web/config/temporal/schedules.yml` or similar:

```yaml
dismissed_asset_cleanup:
  workflow: Workflows::DismissedAssetCleanupWorkflow
  cron: "0 3 * * *"   # Daily at 3 AM UTC
  task_queue: default
```

### Safety Guarantees

The query explicitly requires:
1. `status = "dismissed"` — never active or pending_review
2. `reviewed_at IS NOT NULL` — user explicitly dismissed (not just unreviewed)
3. `reviewed_at < 7.days.ago` — grace period for accidental dismissal

### Files to Touch

- `web/app/temporal/activities/cleanup_dismissed_assets_activity.rb` (new)
- `web/app/temporal/workflows/dismissed_asset_cleanup_workflow.rb` (new)
- Temporal workflow registration config
- Temporal schedules config
- `web/test/temporal/activities/cleanup_dismissed_assets_activity_test.rb` (new)

### Dependencies

- **Requires Story 16.4** — `Asset.dismissed` scope, `reviewed_at` column

### References

- [Source: ai/epics/epic-16-session-outputs-and-config-normalization.md#Story 16.8]
- [Source: web/app/temporal/workflows/stale_session_cleanup_workflow.rb — workflow pattern]
- [Source: web/app/temporal/activities/cleanup_stale_sessions_activity.rb — activity pattern]
- [Source: web/app/models/asset.rb — scopes]
- [Source: web/app/uploaders/asset_file_uploader.rb — Shrine activerecord plugin handles deletion]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
