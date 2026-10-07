# frozen_string_literal: true

module Chat
  # Starts a workflow a linked person chose in a messenger, as that person
  # (docs/design/teams-integration.md §20). The request is recorded as the
  # messenger's `chat.message` that no trigger is matched against, so the run
  # gets the same chat origin and status card a triggered one does.
  module RunStarter
    class Refused < StandardError; end

    module_function

    # `dedup_key` names the request in the messenger: a retried delivery of it
    # must not start a second run.
    def start!(integration:, user:, entry:, source:, subject:, data:, dedup_key:)
      event = record(integration, user, entry, source, subject, data, dedup_key)
      run = TriggerEngine.fire_workflow(workflow: entry.workflow, project: entry.project, actor: user, event: event,
                                        source: ACTION_SOURCE)
      unless run&.persisted?
        raise Refused, "#{entry.workflow.name} did not start: #{run&.errors&.full_messages&.to_sentence.presence || 'it was skipped'}"
      end

      run
    end

    # What an earlier delivery of the same request already recorded.
    def recorded(dedup_key) = TriggerEvent.find_by(dedup_key: dedup_key)

    def record(integration, user, entry, source, subject, data, dedup_key)
      TriggerEngine.record_event(event_type: EVENT_TYPE, source: source, subject: subject, project: entry.project,
                                 company: integration.company, actor: user, dedup_key: dedup_key,
                                 relay_state: "dispatched", data: data.compact)
    rescue ActiveRecord::RecordNotUnique
      TriggerEvent.find_by!(dedup_key: dedup_key)
    end
  end
end
