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
      return false unless Chat.provider_for(dispatch.trigger_event)

      case reporting(dispatch)
      when "lifecycle" then true
      when "failures" then transition.nil? || transition.to_s == "failed"
      else false
      end
    end

    def report(dispatch, transition)
      provider = Chat.provider_for(dispatch.trigger_event)
      return if provider.nil?
      return StatusCard.call(dispatch, provider) if reporting(dispatch) == "lifecycle"
      return unless transition.to_s == "failed"

      run = dispatch.workflow_run&.reload
      # A late or duplicated job acts on what the run is now.
      provider.report_failure(run) if run&.failed?
    end

    # A trigger says how it reports; a run a person started themselves is followed.
    def reporting(dispatch)
      binding = dispatch.trigger_binding
      return binding.status_reporting.to_s if binding&.chat?

      binding.nil? && dispatch.source == Chat::ACTION_SOURCE ? "lifecycle" : "none"
    end
  end
end
