# frozen_string_literal: true

module Slack
  # Downloads files attached to a Slack message (via the install's bot token,
  # files:read) and stores each as a project-scoped Asset, returning the asset
  # ids so they can be passed into the workflow run as input_asset_ids. Per-file
  # failures are logged and skipped, never raised — a bad attachment must not lose
  # the trigger. (Re-ingestion of the same message is already prevented upstream by
  # the ReceivedWebhook event_id dedup.)
  class FileIngestor
    MAX_FILES = 10
    MAX_BYTES = 50 * 1024 * 1024 # 50 MB

    def initialize(integration:, project:)
      @integration = integration
      @project = project
    end

    # files: array of normalized file hashes (id, name, url_private, mimetype, size).
    # Returns the created Asset ids.
    def ingest(files)
      token = @integration.credentials_data["bot_token"]
      return [] if token.blank? || files.blank?

      Array(files).first(MAX_FILES).filter_map { |file| ingest_one(file, token) }
    end

    private

    def ingest_one(file, token)
      return nil if file["size"].to_i > MAX_BYTES

      url = file["url_private_download"].presence || file["url_private"].presence
      return nil if url.blank?
      # SSRF guard: only ever send the bot token to a Slack file host. The url
      # comes from the (signed) Slack payload, but a compromised workspace could
      # otherwise point us at an internal/metadata address.
      return nil unless slack_file_url?(url)

      body = Slack::Client.download_file(url: url, token: token, max_bytes: MAX_BYTES)
      create_asset(file, body).id
    rescue Slack::Client::Error, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[Slack::FileIngestor] failed for file #{file['id']}: #{e.message}")
      nil
    end

    def slack_file_url?(url)
      uri = URI.parse(url.to_s)
      uri.scheme == "https" && uri.host.to_s.downcase.end_with?(".slack.com")
    rescue URI::InvalidURIError
      false
    end

    def create_asset(file, body)
      filename = file["name"].presence || "slack-file"
      tmp = Tempfile.new([ "slack-", File.extname(filename) ])
      tmp.binmode
      tmp.write(body)
      tmp.rewind
      tmp.define_singleton_method(:original_filename) { filename }

      asset = build_asset(filename)
      AssetVersion.create!(
        asset: asset, uploaded_by: @integration.connected_by, source: :slack,
        file: tmp, file_size: body.bytesize, content_type: file["mimetype"]
      )
      asset
    ensure
      tmp&.close!
    end

    # Asset names are unique per (scope, folder); on a clash, disambiguate with a
    # short random suffix so two messages can share an attachment filename.
    def build_asset(filename)
      Asset.create!(asset_attrs(filename))
    rescue ActiveRecord::RecordInvalid
      base = File.basename(filename, ".*")
      Asset.create!(asset_attrs("#{base}-#{SecureRandom.hex(3)}#{File.extname(filename)}"))
    end

    def asset_attrs(name)
      { name: name, folder: "slack", scope: @project, created_by: @integration.connected_by, status: "active" }
    end
  end
end
