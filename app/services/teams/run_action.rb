# frozen_string_literal: true

module Teams
  # The invokes behind "Run workflow" on a message and the /run card
  # (docs/design/teams-integration.md §20). Each answers in the same HTTP
  # response, which Teams waits for at most five seconds.
  module RunAction
    COMMAND = "runWorkflow"
    VERB = "run"
    NOT_HERE = "Add Aixle Flow to this conversation first, then try again."
    GONE = "You can't start that workflow from Teams (any more)."

    module_function

    # composeExtension/fetchTask: the dialog, or why there is none.
    def fetch(integration, activity)
      return notice_dialog("Unknown command") unless activity.dig("value", "commandId") == COMMAND
      return notice_dialog(NOT_HERE) if conversation(integration, activity).nil?

      user = sender(integration, activity)
      return dialog("Link your Aixle account", RunCards.link(link_url(integration, activity))) if user.nil?

      entries = RunCatalog.entries(user, integration)
      return notice_dialog("There is no workflow you can start from Teams in #{integration.company.name}.") if entries.empty?

      payload = activity.dig("value", "messagePayload").to_h
      message = { "message_id" => payload["id"], "reply_to" => payload["replyToId"], "url" => payload["linkToMessage"],
                  "text" => Messages.text(payload.dig("body", "content"), payload.dig("body", "contentType")).truncate(4000) }
      dialog("Run workflow", RunCards.picker(entries, data: message.compact))
    end

    # composeExtension/submitAction: start the chosen workflow on that message.
    def submit(integration, activity)
      data = activity.dig("value", "data").to_h
      conversation = conversation(integration, activity)
      return notice_dialog(NOT_HERE) if conversation.nil?

      user = sender(integration, activity)
      return dialog("Link your Aixle account", RunCards.link(link_url(integration, activity))) if user.nil?

      entry = RunCatalog.find(user, integration, data["workflow"])
      return notice_dialog(GONE) if entry.nil?

      root = activity.dig("conversation", "id").to_s.split(";messageid=", 2)[1]
      thread_id = (root.presence || data["reply_to"].presence || data["message_id"] if conversation.kind == "channel")
      text = [ data["text"].presence, (data["notes"].presence && "Notes: #{data['notes']}") ].compact.join("\n\n")
      RunStarter.start!(integration: integration, user: user, entry: entry, conversation: conversation,
                        invoke_id: activity["id"],
                        request: { thread_id: thread_id, message_id: data["message_id"], text: text,
                                   url: data["url"], actor: actor(integration, activity) })
      # Closing the dialog is the answer: the status card appears in the thread.
      {}
    rescue RunStarter::Refused => e
      notice_dialog(e.message)
    end

    # adaptiveCard/action from the /run card: start it, then show the clicker
    # what happened in place of the form. In a channel the run gets a thread of
    # its own, opened by a line saying who started what.
    def execute(integration, activity)
      action = activity.dig("value", "action").to_h
      return card_response(RunCards.notice("Unknown action")) unless action["verb"] == VERB

      conversation = conversation(integration, activity)
      return card_response(RunCards.notice(NOT_HERE)) if conversation.nil?

      user = sender(integration, activity)
      return card_response(RunCards.link(link_url(integration, activity))) if user.nil?

      data = action["data"].to_h
      entry = RunCatalog.find(user, integration, data["workflow"])
      return card_response(RunCards.notice(GONE)) if entry.nil?

      # A retried invoke reuses the thread its first delivery opened.
      thread_id = RunStarter.recorded(activity["id"])&.data&.dig("thread_id")
      opened = thread_id.nil? && conversation.kind == "channel"
      thread_id = open_thread(conversation, user, entry) if opened
      begin
        run = RunStarter.start!(integration: integration, user: user, entry: entry, conversation: conversation,
                                invoke_id: activity["id"],
                                request: { thread_id: thread_id, message_id: thread_id, text: data["notes"].presence || "/run",
                                           actor: actor(integration, activity) })
      rescue RunStarter::Refused
        close_thread(conversation, thread_id) if opened
        raise
      end
      card_response(RunCards.started(entry, run))
    rescue RunStarter::Refused, Teams::Error => e
      card_response(RunCards.notice(e.message))
    end

    def open_thread(conversation, user, entry)
      response = ConnectorClient.start_thread(
        conversation.teams_reference, channel_id: conversation.external_id,
                                      activity: { type: "message", textFormat: "markdown",
                                                  text: "▶️ **#{Notifier.escape(user.name)}** started **#{Notifier.escape(entry.workflow.name)}**" }
      )
      response["activityId"].presence || response["id"].to_s.split(";messageid=", 2)[1]
    end

    # The opening line of a run that did not start says nothing true.
    def close_thread(conversation, thread_id)
      ConnectorClient.delete(conversation.teams_reference(thread_id: thread_id), thread_id)
    rescue Teams::Error => e
      Rails.logger.warn("[Teams::RunAction] could not remove the opening of thread #{thread_id}: #{e.message}")
    end

    # A conversation the bot is in: only there can the status card follow the run.
    def conversation(integration, activity)
      external_id = activity.dig("conversation", "id").to_s.split(";messageid=", 2).first
      external_id = activity.dig("channelData", "channel", "id").presence || external_id if channel?(activity)
      ChatConversation.find_by(integration: integration, external_id: external_id, installed: true)
    end

    def channel?(activity) = activity.dig("conversation", "conversationType") == "channel"

    def sender(integration, activity)
      Sender.user(integration.settings.to_h["tenant_id"], activity.dig("from", "aadObjectId"))
    end

    def actor(integration, activity)
      from = activity["from"].to_h
      { "id" => from["aadObjectId"], "name" => from["name"],
        "aixle_user_id" => Sender.user_id(integration.settings.to_h["tenant_id"], from["aadObjectId"]) }.compact
    end

    def link_url(integration, activity)
      AccountLink.url_for(integration: integration, tenant_id: integration.settings.to_h["tenant_id"],
                          object_id: activity.dig("from", "aadObjectId"))
    end

    def dialog(title, card)
      { task: { type: "continue", value: { title: title, height: "medium", width: "medium", card: RunCards.attachment(card) } } }
    end

    # A short pop-up (`task.type: message`) showed as "Unable to reach app" on
    # staging, so even a refusal is a small dialog.
    def notice_dialog(text) = dialog("Aixle Flow", RunCards.notice(text))

    def card_response(card) = { statusCode: 200, type: "application/vnd.microsoft.card.adaptive", value: card }
  end
end
