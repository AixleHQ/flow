# frozen_string_literal: true

module Teams
  # What the chat tools do in Teams (docs/design/teams-integration.md §8.3): post,
  # edit and delete as the bot, and read a thread through Graph under the
  # resource-specific consent the app package asks for.
  module Messages
    CARD = "application/vnd.microsoft.card.adaptive"

    Posted = Struct.new(:message_id, :thread_id, keyword_init: true)

    module_function

    # A channel message without a thread starts one: Teams has no other way to
    # post at a channel's top level.
    def post(conversation, thread_id:, new_thread:, text:, card:)
      activity = activity(text, card)
      if conversation.channel? && (new_thread || thread_id.blank?)
        response = ConnectorClient.start_thread(conversation.teams_reference, channel_id: conversation.external_id,
                                                                              activity: activity)
        id = response["activityId"].presence || response["id"].to_s.split(";messageid=", 2).last
        return Posted.new(message_id: id, thread_id: id)
      end

      thread = thread_id if conversation.channel?
      response = ConnectorClient.send_message(conversation.teams_reference(thread_id: thread), activity)
      Posted.new(message_id: response["id"], thread_id: thread)
    end

    def update(conversation, thread_id:, message_id:, text:, card:)
      ConnectorClient.update(reference(conversation, thread_id), message_id, activity(text, card))
    end

    def delete(conversation, thread_id:, message_id:)
      ConnectorClient.delete(reference(conversation, thread_id), message_id)
    end

    def activity(text, card)
      { type: "message", textFormat: "markdown", text: text.presence,
        attachments: ([ { contentType: CARD, content: card } ] if card) }.compact
    end

    # The latest `limit` messages of a channel thread or a group chat, oldest
    # first. Personal chats have no resource-specific consent, so no reads.
    def read_thread(conversation, thread_id:, limit:)
      tenant = conversation.tenant_id
      messages = if conversation.channel?
        base = "teams/#{escape(group_id(conversation))}/channels/#{escape(conversation.external_id)}/messages/#{escape(thread_id)}"
        root = GraphClient.get(tenant, base)
        replies = Array(GraphClient.get(tenant, "#{base}/replies", "$top" => limit)["value"])
        [ root, *replies.sort_by { |message| message["createdDateTime"].to_s } ].last(limit)
      else
        Array(GraphClient.get(tenant, "chats/#{escape(conversation.external_id)}/messages",
                              "$top" => limit, "$orderby" => "createdDateTime desc")["value"]).reverse
      end
      messages.reject { |message| message["messageType"].to_s.start_with?("system") }.map { |message| fields(message) }
    end

    def fields(message)
      from = message["from"].to_h
      {
        id: message["id"],
        from: from.dig("user", "displayName") || from.dig("application", "displayName"),
        bot: from["application"].present?,
        at: message["createdDateTime"],
        text: text(message.dig("body", "content"), message.dig("body", "contentType")),
        files: Array(message["attachments"]).filter_map { |attachment| attachment["name"] }.presence
      }.compact
    end

    def text(content, type)
      return content.to_s.strip unless type.to_s == "html"

      CGI.unescapeHTML(Rails::HTML5::FullSanitizer.new.sanitize(content.to_s.gsub(%r{<br\s*/?>|</p>}i, "\n"))).strip
    end

    # Graph names a team by its Microsoft 365 group, which the Connector reports.
    def group_id(conversation)
      return conversation.team_aad_group_id if conversation.team_aad_group_id.present?

      group = ConnectorClient.team(conversation.teams_reference, conversation.team_external_id)["aadGroupId"]
      conversation.update!(team_aad_group_id: group)
      group
    end

    def reference(conversation, thread_id)
      conversation.teams_reference(thread_id: (thread_id if conversation.channel?))
    end

    def escape(id) = ERB::Util.url_encode(id.to_s)
  end
end
