# frozen_string_literal: true

module InternalTools
  # Platform tool: edit a message the bot posted in Slack or Microsoft Teams —
  # a status line that fills in as a step progresses.
  class ChatUpdateMessage < Base
    include Concerns::ChatContext
    include Concerns::SlackContext

    tool do
      display_name "Chat Update Message"
      description "Edit a message the bot posted in Slack or Microsoft Teams, by the message_id chat_post_message returned. The message is REPLACED, not merged: send everything it should end up with. Only the bot's own messages can be edited. Pass the same conversation and thread the message was posted to when they are not the ones this run was started from."
      tags :messaging, :chat
      inject_when :workflow_step_session
      requires_integration :chat
      idempotent
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
          message_id: { type: "string", description: "The message to edit, as chat_post_message returned it." },
          text: { type: "string", description: "New message text in Markdown." },
          slack_blocks: { type: "array", items: { type: "object" }, description: Concerns::SlackContext::BLOCK_KIT_GUIDE },
          adaptive_card: { type: "object", description: Concerns::ChatContext::ADAPTIVE_CARD_GUIDE }
        }
      })
    end

    def execute
      provider, provider_error = chat_provider
      return provider_error if provider_error

      mismatch = wrong_payload(provider)
      return mismatch if mismatch

      provider == "teams" ? update_teams : update_slack
    end

    private

    def update_slack
      blocks, blocks_error = build_blocks(params[:slack_blocks])
      return blocks_error if blocks_error

      blocks = blocks.presence || slack_markdown_blocks(params[:text])
      return error("Provide `text` and/or `slack_blocks` to replace the message with") if params[:text].blank? && blocks.empty?

      integration, channel, target_error = resolve_slack_target(params[:conversation])
      return target_error if target_error

      _response, call_error = slack_call do
        Slack::Client.update_message(token: slack_bot_token(integration), channel: channel, ts: params[:message_id].to_s,
                                     text: params[:text].presence, blocks: blocks.presence)
      end
      call_error || success("Updated #{params[:message_id]} in #{channel}")
    end

    def update_teams
      card, card_error = adaptive_card
      return card_error if card_error
      return error("Provide `text` and/or `adaptive_card` to replace the message with") if params[:text].blank? && card.nil?

      conversation, target_error = teams_target
      return target_error if target_error

      Teams::Messages.update(conversation, thread_id: teams_thread(conversation), message_id: params[:message_id].to_s,
                                           text: params[:text], card: card)
      success("Updated #{params[:message_id]}")
    rescue Teams::Error => e
      teams_failure(e)
    end
  end
end
