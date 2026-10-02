# frozen_string_literal: true

module Chat
  # Tells the conversation a run came from what became of it, on the shared
  # run-transition seam (Triggers::ORIGIN_REPORTERS). A failed run's agent may
  # never get to say so itself, and the person who asked is waiting in the thread.
  #
  # Only the failure notice so far; the status card that follows a whole run
  # (status_reporting: lifecycle) comes with Teams.
  module RunStatusReporter
    module_function

    def applies?(dispatch)
      binding = dispatch.trigger_binding
      return false unless binding&.chat? && binding.status_reporting.to_s != "none"

      Chat.provider_for(dispatch.trigger_event).present?
    end

    def report(dispatch, transition)
      return unless transition.to_s == "failed"

      run = dispatch.workflow_run&.reload
      # A late or duplicated job acts on what the run is now.
      return unless run&.failed?

      Chat.provider_for(dispatch.trigger_event)&.report_failure(run)
    end
  end
end
