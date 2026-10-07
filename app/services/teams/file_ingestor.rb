# frozen_string_literal: true

module Teams
  # The files a Teams message carried, stored as project assets at fire time, the
  # way Slack's are (docs/design/teams-integration.md §8.5). Each project a message
  # fans out to gets its own copy. A file that cannot be fetched is skipped and
  # logged; it never loses the trigger.
  class FileIngestor
    MAX_FILES = 10

    # A project asset holding these bytes, named uniquely within the teams folder.
    def self.store(project:, user:, filename:, bytes:, content_type: nil)
      tmp = Tempfile.new([ "teams-", File.extname(filename) ])
      tmp.binmode
      tmp.write(bytes)
      tmp.rewind
      tmp.define_singleton_method(:original_filename) { filename }
      asset = begin
        Asset.create!(name: filename, folder: "teams", scope: project, created_by: user, status: "active")
      rescue ActiveRecord::RecordInvalid
        Asset.create!(name: "#{File.basename(filename, '.*')}-#{SecureRandom.hex(3)}#{File.extname(filename)}",
                      folder: "teams", scope: project, created_by: user, status: "active")
      end
      AssetVersion.create!(asset: asset, uploaded_by: user, source: :teams, file: tmp, file_size: bytes.bytesize,
                           content_type: content_type.presence || Marcel::MimeType.for(name: filename))
      asset
    ensure
      tmp&.close!
    end

    def initialize(integration:, project:)
      @integration = integration
      @project = project
    end

    # `files` is the event's metadata; `refs` says, entry by entry, where each
    # file's bytes are.
    def ingest(files, refs)
      Array(files).zip(Array(refs)).first(MAX_FILES).filter_map do |file, ref|
        bytes = fetch(ref.to_h)
        create_asset(file.to_h, bytes).id if bytes
      rescue Teams::Error, ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[Teams::FileIngestor] #{file.to_h['name']}: #{e.message}")
        nil
      end
    end

    private

    def fetch(ref)
      tenant = @integration.settings.to_h["tenant_id"]
      case ref["kind"]
      when "download" then Files.download_link(ref["url"])
      when "share" then Files.download_shared(tenant, ref["url"], allowed_drive: allowed_drive(ref)) if file_access?
      when "hosted" then Files.download_hosted(tenant, ref["path"])
      end
    end

    def file_access? = @integration.settings.to_h["file_access"].present?

    def allowed_drive(ref)
      conversation = @integration.chat_conversations.find_by(external_id: ref["conversation"])
      return nil if conversation.nil?

      conversation.channel? ? Files.channel_drive(conversation) : Files.user_drive(conversation.tenant_id, ref["sender"])
    end

    def create_asset(file, bytes)
      filename = File.basename(file["name"].to_s)
      filename = "teams-file" unless SafeRelativePath.valid?(filename)
      self.class.store(project: @project, user: @integration.connected_by, filename: filename, bytes: bytes,
                                content_type: file["mimetype"])
    end
  end
end
