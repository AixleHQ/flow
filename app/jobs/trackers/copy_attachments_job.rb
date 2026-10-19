# frozen_string_literal: true

module Trackers
  # A tracker trigger with `copy_attachments` started a run: copy the issue's
  # files onto the run's task (docs/design/tracker-attachments.md §7.5). The
  # first step may start before this ends; it gets what is copied by then, and
  # the run's context says what was left out.
  class CopyAttachmentsJob < ApplicationJob
    queue_as :default

    class RunNotVisible < StandardError; end

    # Enqueued inside the dispatch transaction; the run may not be readable yet.
    retry_on RunNotVisible, wait: 2.seconds, attempts: 5

    def perform(workflow_run_id)
      run = WorkflowRun.find_by(id: workflow_run_id)
      raise RunNotVisible, "workflow run #{workflow_run_id}" unless run

      context = run.shared_context.to_h["tracker"].to_h
      tracker = ProjectTracker.find_by(id: context["project_tracker_id"])
      issue = context["issue"].to_h
      return unless run.board_task && tracker&.usable? && issue["id"].present?

      results = AttachmentImporter.new(project_tracker: tracker, task: run.board_task, user: run.user)
                                  .import(issue["id"], issue_key: issue["key"])
      remember(run, results)
    rescue Trackers::Error => e
      Rails.logger.warn("[Trackers::CopyAttachmentsJob] run #{workflow_run_id}: #{e.code} #{e.message}")
    end

    private

    # Into the run's context without rewriting the rest of it: steps write there too.
    def remember(run, results)
      summary = {
        "copied" => results.count { |r| r.status != :skipped },
        "skipped" => results.select { |r| r.status == :skipped }.map { |r| { "name" => r.attachment.name, "reason" => r.reason }.compact }
      }
      WorkflowRun.where(id: run.id).update_all(
        [ "shared_context = jsonb_set(shared_context, '{tracker,files}', ?::jsonb, true)", summary.to_json ]
      )
    end
  end
end
