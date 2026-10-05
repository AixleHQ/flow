# frozen_string_literal: true

module Chat
  # Microsoft Teams behind the messaging port: a Bot Framework activity in, the
  # `chat.message` contract out (docs/design/teams-integration.md §7.3–7.4), and
  # Teams::Notifier for what the platform says back.
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
      files, file_refs = attached_files(endpoint, activity, kind)
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
          "files" => files,
          # Where each file's bytes are, read at fire time and scrubbed after
          # (Webhooks::ProcessEventJob): a 1:1 download link needs no token.
          "file_refs" => file_refs,
          "url" => message_url(endpoint, activity, kind)
        }.compact
      }
    end

    # Teams' documented deep links to a message: a channel thread's names its
    # team's group, which the registry learns when the app is installed.
    def message_url(endpoint, activity, kind)
      conversation_id, root_id = activity.dig("conversation", "id").to_s.split(";messageid=", 2)
      return nil unless conversation_id.start_with?("19:") && activity["id"].present?

      base = "https://teams.microsoft.com/l/message/#{conversation_id}/#{activity['id']}"
      return "#{base}?context=%7B%22contextType%22:%22chat%22%7D" unless kind == "channel"

      channel_data = activity["channelData"].to_h
      group = ChatConversation.where(integration_id: endpoint.config.to_h["integration_id"], external_id: conversation_id)
                              .pick(:team_aad_group_id)
      query = { tenantId: channel_data.dig("tenant", "id"), groupId: group, parentMessageId: root_id || activity["id"],
                teamName: channel_data.dig("team", "name"), channelName: channel_data.dig("channel", "name") }.compact
      "#{base}?#{URI.encode_www_form(query)}"
    end

    def help_request?(event)
      event.data.to_h["text"].to_s.match?(HELP_COMMAND)
    end

    def answer_help(event) = Teams::HelpResponder.call(event)

    def report_failure(run) = Teams::RunFailureNotifier.call(run)

    def post_status_card(event, status) = Teams::StatusCard.post(event, status)

    def update_status_card(event, message_id, status) = Teams::StatusCard.update(event, message_id, status)

    def ingest_files(event, project)
      data = event.data.to_h
      integration = TenantScope.owned(Integration, project: project).find_by(id: data["integration_id"], provider: :teams)
      return nil if integration.nil?

      Teams::FileIngestor.new(integration: integration, project: project).ingest(data["files"], data["file_refs"])
    end

    # A file link that works without a token is a credential while it lives, so
    # nothing keeps one once the message has been handled.
    def scrub(data)
      data.to_h.except("file_refs")
    end

    def scrub_payload(activity)
      return activity unless activity.is_a?(Hash)

      attachments = Array(activity["attachments"]).map do |attachment|
        next attachment unless attachment.is_a?(Hash) && attachment["content"].is_a?(Hash)

        attachment.merge("content" => attachment["content"].except("downloadUrl"))
      end
      activity.merge("attachments" => attachments)
    end

    def run_context(event)
      data = event.data.to_h
      { "chat" => data.slice("provider", "integration_id", "conversation", "thread_id", "message_id", "actor", "url")
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

    # [metadata, refs], index for index. Only a 1:1 message carries its files;
    # in a channel or group chat the bot gets an HTML mirror that marks
    # attachments and pasted images, and the message itself is read from Graph.
    def attached_files(endpoint, activity, kind)
      return direct_files(activity["attachments"]) if kind == "direct"

      html = Array(activity["attachments"]).find { |a| a.is_a?(Hash) && a["contentType"] == "text/html" }.to_h["content"].to_s
      return [ nil, nil ] unless html.include?("<attachment") || html.include?("hostedContents")

      graph_files(endpoint, activity, kind)
    end

    def direct_files(attachments)
      pairs = Array(attachments).filter_map do |attachment|
        next unless attachment.is_a?(Hash) && attachment["contentType"] == "application/vnd.microsoft.teams.file.download.info"

        content = attachment["content"].to_h
        [ { "name" => attachment["name"], "file_type" => content["fileType"], "unique_id" => content["uniqueId"],
            "mimetype" => Marcel::MimeType.for(name: attachment["name"].to_s) }.compact,
          { "kind" => "download", "url" => content["downloadUrl"] } ]
      end
      pairs.empty? ? [ nil, nil ] : pairs.transpose
    end

    def graph_files(endpoint, activity, kind)
      conversation = ChatConversation.find_by(integration_id: endpoint.config.to_h["integration_id"],
                                              external_id: activity.dig("conversation", "id").to_s.split(";messageid=", 2).first)
      return [ nil, nil ] if conversation.nil?

      path = message_path(conversation, activity, kind)
      message = Teams::GraphClient.get(conversation.tenant_id, path)
      pairs = Array(message["attachments"]).filter_map do |attachment|
        next unless attachment["contentType"] == "reference" && attachment["contentUrl"].present?

        [ { "name" => attachment["name"], "mimetype" => Marcel::MimeType.for(name: attachment["name"].to_s) }.compact,
          { "kind" => "share", "url" => attachment["contentUrl"], "conversation" => conversation.external_id,
            "sender" => activity.dig("from", "aadObjectId") } ]
      end
      pairs += hosted_images(message.dig("body", "content"), path)
      pairs.empty? ? [ nil, nil ] : pairs.transpose
    rescue Teams::Error => e
      Rails.logger.warn("[Chat::TeamsProvider] could not read the files of message #{activity['id']}: #{e.message}")
      [ nil, nil ]
    end

    def message_path(conversation, activity, kind)
      esc = ->(id) { ERB::Util.url_encode(id.to_s) }
      return "chats/#{esc[conversation.external_id]}/messages/#{esc[activity['id']]}" unless kind == "channel"

      root = activity.dig("conversation", "id").to_s.split(";messageid=", 2)[1]
      base = "teams/#{esc[Teams::Messages.group_id(conversation)]}/channels/#{esc[conversation.external_id]}/messages"
      root.present? && root != activity["id"] ? "#{base}/#{esc[root]}/replies/#{esc[activity['id']]}" : "#{base}/#{esc[activity['id']]}"
    end

    # Pasted images live with the message: only an <img> of this message's own
    # hosted content is taken, never a path someone typed into the text.
    def hosted_images(html, message_path)
      sources = html.to_s.scan(/<img\b[^>]*\bsrc="([^"]+)"/i).flatten
      ids = sources.filter_map { |src| src[%r{/hostedContents/([A-Za-z0-9_=-]+)/\$value\z}, 1] }.uniq
      ids.each_with_index.map do |id, index|
        [ { "name" => "image-#{index + 1}.png", "mimetype" => "image/png" },
          { "kind" => "hosted", "path" => "#{message_path}/hostedContents/#{id}/$value" } ]
      end
    end
  end
end
