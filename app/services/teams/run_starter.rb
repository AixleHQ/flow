# frozen_string_literal: true

module Teams
  # Starts a workflow a linked person chose in Teams, as that person
  # (docs/design/teams-integration.md §20). The request is recorded as a Teams
  # `chat.message` that no trigger is matched against, so the run gets the same
  # chat origin and status card a triggered one does.
  module RunStarter
    class Refused < StandardError; end

    module_function

    # `invoke_id` is the Teams activity that asked: Teams retries an invoke it
    # waited too long for, and the retry must not start a second run.
    def start!(integration:, user:, entry:, conversation:, request:, invoke_id:)
      event = record(integration, user, entry, conversation, request, invoke_id)
      run = TriggerEngine.fire_workflow(workflow: entry.workflow, project: entry.project, actor: user, event: event,
                                        source: Chat::ACTION_SOURCE)
      unless run&.persisted?
        raise Refused, "#{entry.workflow.name} did not start: #{run&.errors&.full_messages&.to_sentence.presence || 'it was skipped'}"
      end

      run
    end

    def dedup_key(invoke_id) = "teams-invoke:#{invoke_id}"

    # What an earlier delivery of the same invoke already recorded.
    def recorded(invoke_id) = TriggerEvent.find_by(dedup_key: dedup_key(invoke_id))

    def record(integration, user, entry, conversation, request, invoke_id)
      tenant_id = integration.settings.to_h["tenant_id"]
      TriggerEngine.record_event(
        event_type: Chat::EVENT_TYPE, source: "teams:#{Connection.endpoint_slug(tenant_id)}",
        subject: conversation.external_id, project: entry.project, company: integration.company, actor: user,
        dedup_key: dedup_key(invoke_id), relay_state: "dispatched",
        data: {
          "provider" => Chat::TeamsProvider::KEY, "integration_id" => integration.id, "workspace" => { "id" => tenant_id },
          "conversation" => { "id" => conversation.external_id, "type" => conversation.kind, "name" => conversation.name }.compact,
          "channel" => conversation.external_id, "thread_id" => request[:thread_id], "message_id" => request[:message_id],
          "actor" => request[:actor], "text" => request[:text], "url" => request[:url]
        }.compact
      )
    rescue ActiveRecord::RecordNotUnique
      TriggerEvent.find_by!(dedup_key: dedup_key(invoke_id))
    end
  end
end
