# frozen_string_literal: true

module Trackers
  # A tracker trigger with `copy_attachments` started a run: copy the issue's
  # files onto the run's task (docs/design/tracker-attachments.md §7.5). The run
  # is marked pending until this stops (Trackers::IssueFileCopy); its first step
  # waits for that, within a bound.
  class CopyAttachmentsJob < ApplicationJob
    queue_as :default

    class RunNotVisible < StandardError; end
    class PoolNearLimit < StandardError; end

    # Enqueued inside the dispatch transaction; the run may not be readable yet.
    retry_on RunNotVisible, wait: 2.seconds, attempts: 5
    # Jira's pool is shared by every customer (Trackers::Jira::Budget); the
    # copy waits instead of draining it.
    retry_on PoolNearLimit, wait: 10.minutes, attempts: 6 do |job, _error|
      IssueFileCopy.record(job.arguments.first, "error" => "rate_limited")
    end

    def perform(workflow_run_id)
      run = WorkflowRun.find_by(id: workflow_run_id)
      raise RunNotVisible, "workflow run #{workflow_run_id}" unless run

      context = run.shared_context.to_h["tracker"].to_h
      tracker = ProjectTracker.find_by(id: context["project_tracker_id"])
      issue = context["issue"].to_h
      return IssueFileCopy.record(run.id, "error" => "unavailable") unless run.board_task && tracker&.usable? && issue["id"].present?

      results = AttachmentImporter.new(project_tracker: tracker, task: run.board_task, user: run.user,
                                       throttle: throttle(tracker))
                                  .import(issue["id"], issue_key: issue["key"])
      remember(run, results)
    rescue Trackers::Error => e
      Rails.logger.warn("[Trackers::CopyAttachmentsJob] run #{workflow_run_id}: #{e.code} #{e.message}")
      IssueFileCopy.record(workflow_run_id, "error" => e.code)
    end

    private

    def throttle(tracker)
      return unless tracker.provider == "jira"

      integration = tracker.integration
      raise PoolNearLimit, "Jira's rate-limit pool is near its limit" if Jira::Budget.near_limit?(Jira::Budget.pool_for(integration))

      -> { Jira::Budget.take(integration) }
    end

    def remember(run, results)
      IssueFileCopy.record(run.id, {
        "copied" => results.count { |r| r.status != :skipped },
        "skipped" => results.select { |r| r.status == :skipped }.map { |r| { "name" => r.attachment.name, "reason" => r.reason }.compact }
      })
    end
  end
end
