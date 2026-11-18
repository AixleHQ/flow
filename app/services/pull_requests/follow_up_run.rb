# frozen_string_literal: true

module PullRequests
  # When a pull-request run ends, the reviews and comments skipped while it ran
  # (TriggerSupport::SKIP_IN_PROGRESS) start one more run, for the latest of them
  # (docs/design/pull-request-triggers.md §6.2). On the run-transition seam of
  # Triggers::ORIGIN_REPORTERS, which already calls once per dispatch per
  # transition. A cancelled run is someone stopping the work, so it has none.
  module FollowUpRun
    TRANSITIONS = %w[completed failed].freeze

    module_function

    def applies?(dispatch, transition = nil)
      (transition.nil? || TRANSITIONS.include?(transition.to_s)) &&
        dispatch.trigger_binding&.pull_request_event? && TriggerSupport.event?(dispatch.trigger_event)
    end

    def report(dispatch, transition)
      return unless TRANSITIONS.include?(transition.to_s)

      run = dispatch.workflow_run&.reload
      return unless run && run.state.to_s == transition.to_s

      follow_up = TriggerSupport.follow_up_dispatch(run, dispatch.trigger_event.subject)
      return unless follow_up

      TriggerEngine.fire_for_binding(binding: follow_up.trigger_binding, event: follow_up.trigger_event)
    end
  end
end
