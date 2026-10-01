# frozen_string_literal: true

module Trackers
  # The one write the platform makes to a tracker: a comment on the issue whose
  # event started a run that then failed or was cancelled
  # (docs/design/task-tracker-integrations.md §6.9). A failed agent cannot say
  # so itself. Where the issue goes next is the agent's job, never this one's.
  module RunStatusReporter
    TRANSITIONS = %w[failed cancelled].freeze
    RETRYABLE = %w[rate_limited provider_error timeout].freeze

    module_function

    def applies?(dispatch)
      binding = dispatch.trigger_binding
      binding&.tracker_event? && binding.notify_on_failure && TriggerSupport.event?(dispatch.trigger_event)
    end

    def report(dispatch, transition)
      return unless TRANSITIONS.include?(transition.to_s)

      run = dispatch.workflow_run&.reload
      # A late or duplicated job acts on what the run is now, not on what it was.
      return unless run&.state.to_s == transition.to_s

      event = dispatch.trigger_event
      tracker = ProjectTracker.find_by(id: event.data.dig("tracker", "id"))
      return unless tracker&.writable?

      post(tracker, run, event.data.dig("issue", "id"), body(run, transition))
    end

    def post(tracker, run, issue_id, text)
      record, state = TrackerOperation.claim!(
        project_tracker: tracker, key: "run-status:#{run.id}", operation: "add_comment",
        payload: { issue: issue_id, body: text }, issue_id: issue_id.to_s, workflow_run_id: run.id,
        workflow_id: run.workflow_id, chain: Array(run.shared_context.to_h.dig("tracker", "chain"))
      )
      return if state == :replayed && !record.failed?

      record.retry! if record.failed?
      comment = tracker.tracker_provider.add_comment(tracker.external_scope_id, issue_id, text)
      record.succeed!(comment, result_ref: comment.id)
    rescue Error::OutcomeUnknown
      record&.unknown!
    rescue Error => e
      record&.fail!(e.code)
      raise Triggers::ReportToOriginJob::Retryable, e.message if RETRYABLE.include?(e.code)
    end

    def body(run, transition)
      what = transition.to_s == "cancelled" ? "was cancelled" : "failed"
      summary = failure_summary(run) if transition.to_s == "failed"
      [ "Aixle: the #{run.workflow&.name || 'workflow'} run for this issue #{what}.", summary, run_url(run) ]
        .compact_blank.join("\n\n")
    end

    def failure_summary(run)
      step = run.step_runs.where(state: "failed").order(:updated_at).last
      [ step&.step&.name, step&.error_message.to_s.truncate(300).presence ].compact.join(": ").presence ||
        run.failure_reason.to_s.humanize.presence
    end

    def run_url(run)
      "https://#{Settings.domain}/company/projects/#{run.project_id}/workflow_runs/#{run.id}"
    end
  end
end
