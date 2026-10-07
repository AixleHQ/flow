# frozen_string_literal: true

module Chat
  # One card per dispatch in the thread the request came from, edited in place
  # as the run moves (docs/design/teams-integration.md §8.2). It always shows
  # what the run is now, so jobs arriving out of order cannot walk it back; the
  # transition that woke the job only says something may have changed.
  module StatusCard
    Status = Struct.new(:state, :workflow, :run_id, :since, :duration, :detail, :url, :started_by, keyword_init: true) do
      def finished? = %w[completed failed cancelled skipped].include?(state)
    end

    module_function

    def call(dispatch, provider)
      dispatch.with_lock do
        status = status_of(dispatch)
        card = dispatch.detail.to_h["chat_status"].to_h
        unless card["message_id"].present? && card["state"] == status.state
          message_id = card["message_id"].presence
          if message_id
            provider.update_status_card(dispatch.trigger_event, message_id, status)
          else
            message_id = provider.post_status_card(dispatch.trigger_event, status)
          end
          card = { "message_id" => message_id, "state" => status.state }
          dispatch.update!(detail: dispatch.detail.to_h.merge("chat_status" => card))
        end
      end
    end

    def status_of(dispatch)
      run = dispatch.workflow_run
      workflow = (run&.workflow || dispatch.trigger_binding&.workflow)&.name || "Workflow"
      return Status.new(state: "skipped", workflow: workflow, detail: skip_detail(dispatch)) if run.nil?

      # A trigger's run belongs to whoever set the trigger up, not to the person
      # who wrote the message, so only a run someone started themselves names them.
      started_by = run.user&.name if dispatch.source == Chat::ACTION_SOURCE
      base = { workflow: workflow, run_id: run.id, url: Chat::RunFailure.url(run), started_by: started_by }
      case run.state.to_s
      when "pending" then Status.new(state: "accepted", **base)
      when "running", "paused" then Status.new(state: "running", since: run.started_at, **base)
      when "completed" then Status.new(state: "completed", duration: duration(run), **base)
      when "failed" then Status.new(state: "failed", detail: Chat::RunFailure.summary(run), **base)
      else Status.new(state: "cancelled", **base)
      end
    end

    def skip_detail(dispatch)
      reason = dispatch.detail.to_h["reason"].to_s
      reason == "cooldown" ? "This trigger started a run moments ago and is cooling down." : reason.presence
    end

    def duration(run)
      return nil unless run.started_at && run.completed_at

      seconds = (run.completed_at - run.started_at).to_i
      seconds < 60 ? "#{seconds} s" : ActiveSupport::Duration.build((seconds / 60) * 60).inspect
    end
  end
end
