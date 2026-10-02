# frozen_string_literal: true

module Chat
  # Microsoft Teams behind the messaging port: a Bot Framework activity in, the
  # `chat.message` contract out (docs/design/teams-integration.md §7.3–7.4).
  # Saying things back (help, status cards, the agent's tools) comes with the
  # Teams connection.
  module TeamsProvider
    KEY = "teams"
    LABEL = "Microsoft Teams"

    CONVERSATION_TYPES = { "channel" => "channel", "groupChat" => "group", "personal" => "direct" }.freeze
    HELP_COMMAND = %r{\A/?help\z}i

    module_function

    def key = KEY
    def label = LABEL

    def normalize(endpoint, activity)
      return nil unless activity.is_a?(Hash) && activity["type"] == "message"

      conversation = activity["conversation"].to_h
      kind = CONVERSATION_TYPES.fetch(conversation["conversationType"].to_s, "group")
      conversation_id, root_id = conversation["id"].to_s.split(";messageid=", 2)
      channel_data = activity["channelData"].to_h
      tenant_id = channel_data.dig("tenant", "id") || conversation["tenantId"]
      {
        event_type: Chat::EVENT_TYPE,
        subject: conversation_id,
        data: {
          "provider" => KEY,
          "integration_id" => endpoint.config.to_h["integration_id"],
          "workspace" => { "id" => tenant_id }.compact.presence,
          "conversation" => {
            "id" => conversation_id, "type" => kind, "name" => channel_data.dig("channel", "name"),
            "team" => { "id" => channel_data.dig("team", "id"), "name" => channel_data.dig("team", "name") }.compact.presence
          }.compact,
          "channel" => conversation_id,
          # Threads exist in channels only; a channel message with no thread is the root of its own.
          "thread_id" => (root_id || activity["id"] if kind == "channel"),
          "message_id" => activity["id"],
          "actor" => actor(activity["from"].to_h),
          "text" => request_text(activity),
          "raw_text" => activity["text"],
          # Where replies go. Recorded from the authenticated activity; never part
          # of a run's context, so nothing an agent passes can redirect a reply.
          "service_url" => activity["serviceUrl"],
          "files" => files(activity["attachments"])
        }.compact
      }
    end

    def help_request?(event)
      event.data.to_h["text"].to_s.match?(HELP_COMMAND)
    end

    def answer_help(_event) = false

    def report_failure(_run) = false

    def ingest_files(_event, _project) = nil

    def run_context(event)
      data = event.data.to_h
      { "chat" => data.slice("provider", "integration_id", "conversation", "thread_id", "message_id", "actor")
                      .merge("workspace_id" => data.dig("workspace", "id"), "text" => data["raw_text"] || data["text"])
                      .compact_blank }
    end

    def mention(actor)
      actor.to_h["name"].presence
    end

    # Microsoft's rule: the mention is an entity, and its own `text` is what to
    # remove — a name typed by hand is not a mention and stays in the request.
    def request_text(activity)
      text = activity["text"].to_s
      Array(activity["entities"]).each do |entity|
        next unless entity["type"] == "mention" && entity.dig("mentioned", "id") == activity.dig("recipient", "id")

        text = text.gsub(entity["text"].to_s, " ") if entity["text"].present?
      end
      CGI.unescapeHTML(text.gsub(/<[^>]+>/, " ")).tr(" ", " ").squeeze(" ").strip
    end

    def actor(from)
      {
        "id" => from["aadObjectId"],
        "name" => from["name"],
        "aixle_user_id" => aixle_user_id(from["aadObjectId"])
      }.compact.presence
    end

    # The sender's Entra object id is the subject a Microsoft sign-in stores, so
    # a person who signs in to Aixle with Microsoft is recognised here. Never by
    # email: Entra does not verify addresses (docs/design/teams-integration.md §9).
    def aixle_user_id(object_id)
      return nil if object_id.blank?

      UserIdentity.joins(:identity_provider).where(identity_providers: { kind: "microsoft" })
                  .where(subject: object_id).pick(:user_id)
    end

    # Only 1:1 chats carry file details; in a channel the bot sees an HTML mirror
    # and the file lives in SharePoint.
    def files(attachments)
      Array(attachments).filter_map do |attachment|
        next unless attachment.is_a?(Hash) && attachment["contentType"] == "application/vnd.microsoft.teams.file.download.info"

        content = attachment["content"].to_h
        { "name" => attachment["name"], "file_type" => content["fileType"], "unique_id" => content["uniqueId"] }.compact
      end.presence
    end
  end
end
