# frozen_string_literal: true

module Teams
  # Chat::RunStarter for a request made in Teams: the Teams shape of the
  # `chat.message` it records, keyed on the invoke that asked.
  module RunStarter
    Refused = Chat::RunStarter::Refused

    module_function

    # `invoke_id` is the Teams activity that asked: Teams retries an invoke it
    # waited too long for, and the retry must not start a second run.
    def start!(integration:, user:, entry:, conversation:, request:, invoke_id:)
      tenant_id = integration.settings.to_h["tenant_id"]
      Chat::RunStarter.start!(
        integration: integration, user: user, entry: entry, dedup_key: dedup_key(invoke_id),
        source: "teams:#{Connection.endpoint_slug(tenant_id)}", subject: conversation.external_id,
        data: {
          "provider" => Chat::TeamsProvider::KEY, "integration_id" => integration.id, "workspace" => { "id" => tenant_id },
          "conversation" => { "id" => conversation.external_id, "type" => conversation.kind, "name" => conversation.name }.compact,
          "channel" => conversation.external_id, "thread_id" => request[:thread_id], "message_id" => request[:message_id],
          "actor" => request[:actor], "text" => request[:text], "url" => request[:url]
        }
      )
    end

    def dedup_key(invoke_id) = "teams-invoke:#{invoke_id}"

    def recorded(invoke_id) = Chat::RunStarter.recorded(dedup_key(invoke_id))
  end
end
