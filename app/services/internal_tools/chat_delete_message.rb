# frozen_string_literal: true

module InternalTools
  # Platform tool: delete a message the bot posted in Slack or Microsoft Teams.
  class ChatDeleteMessage < Base
    include Concerns::ChatContext
    include Concerns::SlackContext

    tool do
      display_name "Chat Delete Message"
      description "Delete a message the bot posted in Slack or Microsoft Teams, by the message_id chat_post_message returned. Only the bot's own messages can be deleted. Pass the same conversation and thread the message was posted to when they are not the ones this run was started from."
      tags :messaging, :chat
      inject_when :workflow_step_session
      requires_integration :chat
      destructive
      input_schema({
        type: "object",
        required: %w[message_id],
        properties: {
          provider: {
            type: "string", enum: %w[slack teams],
            description: "slack or teams. Defaults to the messenger this run was started from, or the only one connected."
          },
          conversation: {
            type: "string",
            description: "Where: a Slack channel id, or a Teams conversation (\"Team/Channel\", a channel name, or its id). " \
                         "Defaults to the conversation this run was started from."
          },
          thread: {
            type: "string",
            description: "The thread: a Slack thread ts or a Teams thread (root message) id. Defaults to the thread " \
                         "this run was started from, in that conversation."
          },
          message_id: { type: "string", description: "The message to delete, as chat_post_message returned it." }
        }
      })
    end

    def execute
      provider, provider_error = chat_provider
      return provider_error if provider_error

      provider == "teams" ? delete_teams : delete_slack
    end

    private

    def delete_slack
      integration, channel, target_error = resolve_slack_target(params[:conversation])
      return target_error if target_error

      _response, call_error = slack_call do
        Slack::Client.delete_message(token: slack_bot_token(integration), channel: channel, ts: params[:message_id].to_s)
      end
      call_error || success("Deleted #{params[:message_id]} from #{channel}")
    end

    def delete_teams
      conversation, target_error = teams_target
      return target_error if target_error

      Teams::Messages.delete(conversation, thread_id: teams_thread(conversation), message_id: params[:message_id].to_s)
      success("Deleted #{params[:message_id]}")
    rescue Teams::Error => e
      teams_failure(e)
    end
  end
end
