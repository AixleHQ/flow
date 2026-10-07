# frozen_string_literal: true

module Teams
  # Files an agent sends to Teams (docs/design/teams-integration.md §8.5): into a
  # channel's own files, under Aixle/, when the organization granted file
  # access; through a file consent card in a 1:1 chat; and otherwise as links to
  # the project's assets, since the bot has no drive of its own to share from.
  module FileSender
    CONSENT_CARD = "application/vnd.microsoft.teams.card.file.consent"

    module_function

    # One entry per file: its name, how it went out, and its link when it has one.
    # Files are written only into the channel the run was started from — the
    # permission behind the write reaches every channel of the organization.
    def deliver(conversation, thread_id:, files:, project:, user:, origin_conversation: nil)
      if conversation.channel? && conversation.integration.settings.to_h["file_access"] &&
         conversation.external_id == origin_conversation
        to_channel(conversation, thread_id, files)
      elsif conversation.direct?
        files.map { |file| ask_consent(conversation, file, project, user) }
      else
        as_asset_links(conversation, thread_id, files, project, user)
      end
    end

    def to_channel(conversation, thread_id, files)
      items = files.map { |file| Files.upload_to_channel(conversation, safe_name(file[:filename]), file[:content].to_s.b) }
      Messages.post(conversation, thread_id: thread_id, new_thread: false, card: nil,
                                  text: items.map { |item| "📎 [#{Notifier.escape(item['name'])}](#{item['webUrl']})" }.join("\n\n"))
      items.map { |item| { name: item["name"], delivered: "uploaded", url: item["webUrl"] } }
    end

    # The bytes wait as a project asset until the person accepts; the card's
    # context names that asset and this conversation, signed.
    def ask_consent(conversation, file, project, user)
      bytes = file[:content].to_s.b
      raise Error, "#{file[:filename]} is larger than #{Files::MAX_BYTES / 1024 / 1024} MB" if bytes.bytesize > Files::MAX_BYTES

      asset = FileIngestor.store(project: project, user: user, filename: safe_name(file[:filename]), bytes: bytes)
      token = consent_verifier.generate({ "asset_id" => asset.id, "conversation_id" => conversation.id }, expires_in: 7.days)
      ConnectorClient.send_message(conversation.teams_reference, type: "message", attachments: [ {
        contentType: CONSENT_CARD, name: asset.name,
        content: { description: file[:title].presence || asset.name, sizeInBytes: bytes.bytesize,
                   acceptContext: { token: token }, declineContext: { token: token } }
      } ])
      { name: asset.name, delivered: "consent_requested" }
    end

    def as_asset_links(conversation, thread_id, files, project, user)
      assets = files.map { |file| FileIngestor.store(project: project, user: user, filename: safe_name(file[:filename]), bytes: file[:content].to_s.b) }
      url = "#{Settings.protocol}://#{Settings.domain}#{Rails.application.routes.url_helpers.company_project_assets_path(project)}"
      names = assets.map { |asset| Notifier.escape(asset.name) }.join(", ")
      Messages.post(conversation, thread_id: thread_id, new_thread: false, card: nil,
                                  text: "📎 #{names} — in [the project's files in Aixle](#{url})")
      assets.map { |asset| { name: asset.name, delivered: "linked", url: url } }
    end

    def consent_verifier = Rails.application.message_verifier("teams_file_consent")

    def safe_name(name)
      base = File.basename(name.to_s)
      SafeRelativePath.valid?(base) ? base : "file"
    end
  end
end
