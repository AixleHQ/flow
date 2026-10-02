# frozen_string_literal: true

module Teams
  # Tells the Teams thread a run came from that the run failed, and with what.
  # A throttle or an outage is the caller's to retry; any other refusal (the bot
  # was removed, the chat is gone) is logged and dropped.
  module RunFailureNotifier
    module_function

    def call(run)
      origin = Chat.origin(run).to_h
      conversation = Notifier.conversation_for(origin["integration_id"], origin.dig("conversation", "id"))
      return false if conversation.nil? || !conversation.installed?

      Notifier.post(conversation, text: message(run), thread_id: origin["thread_id"])
      true
    rescue Teams::Error => e
      raise Triggers::ReportToOriginJob::Retryable, e.message if e.retryable?

      Rails.logger.error("[Teams::RunFailureNotifier] run ##{run&.id}: #{e.message}")
      false
    end

    def message(run)
      summary = Chat::RunFailure.summary(run)
      [ "❌ **#{Notifier.escape(run.workflow&.name || 'Workflow')}** run ##{run.id} failed.",
        ("> #{summary}" if summary.present?), Chat::RunFailure.url(run) ].compact.join("\n\n")
    end
  end
end
