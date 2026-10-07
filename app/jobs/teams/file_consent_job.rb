# frozen_string_literal: true

module Teams
  # A person accepted a file consent card: the bytes go to the upload link Teams
  # gave, a file card takes the consent card's place.
  class FileConsentJob < ApplicationJob
    queue_as :default

    retry_on Teams::Error, attempts: 3, wait: :polynomially_longer

    FILE_INFO_CARD = "application/vnd.microsoft.teams.card.file.info"

    def perform(conversation_id, asset_id, upload, consent_activity_id = nil)
      conversation = ChatConversation.find_by(id: conversation_id)
      version = Asset.find_by(id: asset_id)&.latest_version
      return if conversation.nil? || version&.file.nil?

      Files.upload_consented(upload["uploadUrl"], version.file.download(&:read))
      ConnectorClient.send_message(conversation.teams_reference, type: "message", attachments: [ {
        contentType: FILE_INFO_CARD, contentUrl: upload["contentUrl"], name: upload["name"],
        content: { uniqueId: upload["uniqueId"], fileType: upload["fileType"] }
      } ])
      ConnectorClient.delete(conversation.teams_reference, consent_activity_id) if consent_activity_id.present?
    end
  end
end
