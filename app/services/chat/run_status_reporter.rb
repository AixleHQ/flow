# frozen_string_literal: true

module Chat
  # Tells the conversation a run came from what became of it, on the shared
  # run-transition seam (Triggers::ORIGIN_REPORTERS): a status card that follows
  # the run (`lifecycle`), or one message when it fails (`failures`). A failed
  # run's agent may never get to say so itself, and the person who asked is
  # waiting in the thread.
  module RunStatusReporter
    module_function

    def applies?(dispatch, transition = nil)
      binding = dispatch.trigger_binding
      return false unless binding&.chat? && Chat.provider_for(dispatch.trigger_event)

      case binding.status_reporting.to_s
      when "lifecycle" then true
      when "failures" then transition.nil? || transition.to_s == "failed"
      else false
      end
    end

    def report(dispatch, transition)
      provider = Chat.provider_for(dispatch.trigger_event)
      return if provider.nil?
      return StatusCard.call(dispatch, provider) if dispatch.trigger_binding&.status_reporting.to_s == "lifecycle"
      return unless transition.to_s == "failed"

      run = dispatch.workflow_run&.reload
      # A late or duplicated job acts on what the run is now.
      provider.report_failure(run) if run&.failed?
    end
  end
end
