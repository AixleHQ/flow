# frozen_string_literal: true

module InternalTools
  # Platform tool: send a message to Slack or Microsoft Teams
  # (docs/design/teams-integration.md §8.3). One tool for both, so a workflow
  # reads the same whichever messenger started it: text is Markdown, each
  # messenger's rich layout has its own argument, and files arrive natively.
  class ChatPostMessage < Base
    include Concerns::ChatContext
    include Concerns::SlackContext
    include Concerns::ToolFiles

    tool do
      display_name "Chat Post Message"
      description "Send a message to Slack or Microsoft Teams. `text` is Markdown; `slack_blocks` (Block Kit) or `adaptive_card` (Teams) add rich layout; `files` attach files, each entry setting EXACTLY ONE source: `content` (inline text, needs `filename`), `file_path` (a path in the running container, any type), or `asset_id` (a project asset). At least one of text/slack_blocks/adaptive_card/files is required. Omit provider/conversation/thread to answer in the thread the run was started from; `new_thread: true` starts a new thread in that channel instead. Returns JSON {provider, conversation, thread, message_id}; chat_update_message and chat_delete_message take that message_id."
      tags :messaging, :chat
      inject_when :workflow_step_session
      requires_integration :chat
      input_schema({
        type: "object",
        required: [],
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
          new_thread: { type: "boolean", description: "Start a new thread in the channel instead of answering in one." },
          text: { type: "string", description: "Message text in Markdown." },
          slack_blocks: { type: "array", items: { type: "object" }, description: Concerns::SlackContext::BLOCK_KIT_GUIDE },
          adaptive_card: { type: "object", description: Concerns::ChatContext::ADAPTIVE_CARD_GUIDE },
          files: {
            type: "array",
            items: {
              type: "object",
              properties: {
                title: { type: "string", description: "Optional display title (defaults to filename)" },
                filename: { type: "string", description: "File name. Required with `content`." },
                content: { type: "string", description: "Inline text content. Source option 1 of 3." },
                file_path: { type: "string", description: "Path inside the running container. Source option 2 of 3." },
                asset_id: { type: "integer", description: "A project asset's id. Source option 3 of 3." }
              }
            },
            description: "Files to attach. In a Teams channel they need the organization's file access; " \
                         "without it, and in Teams group chats, they are shared as links to project assets."
          }
        }
      })
    end

    def execute
      provider, provider_error = chat_provider
      return provider_error if provider_error

      mismatch = wrong_payload(provider)
      return mismatch if mismatch

      files, file_error = build_files
      return file_error if file_error

      provider == "teams" ? post_to_teams(files) : post_to_slack(files)
    end

    private

    def post_to_slack(files)
      blocks, blocks_error = build_blocks(params[:slack_blocks])
      return blocks_error if blocks_error

      blocks = blocks.presence || slack_markdown_blocks(params[:text])
      return error("Provide `text`, `slack_blocks` and/or `files`") if params[:text].blank? && blocks.empty? && files.empty?

      integration, channel, target_error = resolve_slack_target(params[:conversation])
      return target_error if target_error

      thread = slack_thread(channel)
      result = Slack::Notifier.post(integration: integration, channel: channel, text: params[:text].presence,
                                    blocks: blocks.presence, files: files.presence, thread_ts: thread)
      return error("Failed to send to Slack") if result.nil?
      return error("Partially sent to #{channel} (ts #{result.ts}) — #{result.error_message}") unless result.ok?

      success({ provider: "slack", conversation: channel, thread: thread || result.ts, message_id: result.ts }.to_json)
    end

    def slack_thread(channel)
      return nil if params[:new_thread]

      params[:thread].presence || (slack_context["thread_ts"] if channel == slack_context["channel"])
    end

    def post_to_teams(files)
      card, card_error = adaptive_card
      return card_error if card_error
      if params[:text].blank? && card.nil? && files.empty?
        return error("Provide `text`, `adaptive_card` and/or `files`")
      end

      conversation, target_error = teams_target
      return target_error if target_error

      thread = params[:new_thread] ? nil : teams_thread(conversation)
      if params[:text].present? || card
        posted = Teams::Messages.post(conversation, thread_id: thread, new_thread: params[:new_thread],
                                                    text: params[:text], card: card)
      end
      sent = Teams::FileSender.deliver(conversation, thread_id: posted&.thread_id || thread, files: files, project: project,
                                                     user: session&.user) if files.any?
      success({ provider: "teams", conversation: conversation.external_id, thread: posted&.thread_id || thread,
                message_id: posted&.message_id, files: sent }.compact.to_json)
    rescue Teams::Error => e
      teams_failure(e)
    end
  end
end
