# frozen_string_literal: true

module Trackers
  # The copy of an issue's files that a tracker trigger's run makes onto its task
  # (CopyAttachmentsJob, docs/design/tracker-attachments.md §7.5), as the run's
  # context records it under tracker.files: pending from the dispatch until the
  # job stops, then what it copied or the error that stopped it.
  class IssueFileCopy
    PENDING = { "pending" => true }.freeze

    def self.pending!(run_id) = record(run_id, PENDING)

    # Into the run's context without rewriting the rest of it: steps write there too.
    def self.record(run_id, state)
      WorkflowRun.where(id: run_id).update_all([
        "shared_context = jsonb_set(COALESCE(shared_context, '{}'::jsonb), '{tracker}', " \
        "COALESCE(shared_context -> 'tracker', '{}'::jsonb) || jsonb_build_object('files', ?::jsonb))",
        state.to_json
      ])
    end

    def initialize(run, wait: Settings.trackers.copy_wait_seconds, poll: Settings.trackers.copy_poll_seconds)
      @run = run
      @wait = wait.to_f
      @poll = poll.to_f
    end

    # The copy's state once it has stopped, or as it stands when the wait runs out.
    def await
      deadline = now + @wait
      loop do
        state = current
        return state if !state["pending"] || now >= deadline

        sleep @poll
      end
    end

    private

    def current
      files = WorkflowRun.where(id: @run.id).pick(Arel.sql("shared_context -> 'tracker' -> 'files'"))
      (files.is_a?(String) ? JSON.parse(files) : files).to_h
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
