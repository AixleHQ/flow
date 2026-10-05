# frozen_string_literal: true

module Teams
  # Moving file bytes to and from Microsoft 365 (docs/design/teams-integration.md
  # §8.5). Pre-authenticated links are fetched only from SharePoint and OneDrive
  # hosts, through SafeHttp, and never with a token; Graph is called with the
  # app's own token for the tenant.
  module Files
    MAX_BYTES = 50 * 1024 * 1024
    MAX_UPLOAD_BYTES = 250 * 1024 * 1024
    HOSTS = %w[.sharepoint.com .sharepoint-df.com .1drv.com .onedrive.com].freeze

    module_function

    # A file a 1:1 message carried: its downloadUrl needs no token.
    def download_link(url, max_bytes: MAX_BYTES)
      uri = URI.parse(url.to_s)
      raise Error, "not a Microsoft 365 file link" unless uri.scheme == "https" && HOSTS.any? { |h| uri.host.to_s.downcase.end_with?(h) }

      buffer = +"".b
      response = Faraday.new(url: "#{uri.scheme}://#{uri.host}") { |f| SafeHttp.pin_faraday!(f, uri) }.get(uri.request_uri) do |req|
        req.options.timeout = 60
        req.options.on_data = proc do |chunk, _|
          buffer << chunk
          raise Error, "file exceeds #{max_bytes / 1024 / 1024} MB" if buffer.bytesize > max_bytes
        end
      end
      raise Error.new("download failed: HTTP #{response.status}", status: response.status) unless response.success?

      buffer
    rescue URI::InvalidURIError, SafeHttp::UnsafeUrl => e
      raise Error, e.message
    end

    # A channel or group-chat file, by the link its message's attachment named.
    # Graph answers with a redirect to a short-lived download link.
    def download_shared(tenant_id, content_url, max_bytes: MAX_BYTES)
      share = "u!#{Base64.urlsafe_encode64(content_url.to_s, padding: false)}"
      location = redirect_location(tenant_id, "shares/#{share}/driveItem/content")
      download_link(location, max_bytes: max_bytes)
    end

    # An image pasted into a message, stored with the message itself.
    def download_hosted(tenant_id, graph_path, max_bytes: MAX_BYTES)
      response = graph_connection.get("#{Config.cloud[:graph]}/v1.0/#{graph_path}", nil, auth(tenant_id))
      raise Error.new("hosted content: HTTP #{response.status}", status: response.status) unless response.success?
      raise Error, "file exceeds #{max_bytes / 1024 / 1024} MB" if response.body.bytesize > max_bytes

      response.body
    end

    # Into a channel's own files, under Aixle/; the name is made unique there.
    def upload_to_channel(conversation, filename, bytes)
      raise Error, "#{filename} is larger than #{MAX_UPLOAD_BYTES / 1024 / 1024} MB" if bytes.bytesize > MAX_UPLOAD_BYTES

      tenant = conversation.tenant_id
      group = Messages.group_id(conversation)
      folder = GraphClient.get(tenant, "teams/#{Messages.escape(group)}/channels/#{Messages.escape(conversation.external_id)}/filesFolder")
      drive = folder.dig("parentReference", "driveId")
      path = "drives/#{Messages.escape(drive)}/items/#{Messages.escape(folder['id'])}:/Aixle/#{ERB::Util.url_encode(filename)}:/content"
      GraphClient.request(tenant, :put, path, query: { "@microsoft.graph.conflictBehavior" => "rename" }, body: bytes,
                                              headers: { "Content-Type" => "application/octet-stream" })
    end

    # Where the bytes go after a person accepted a file consent card.
    def upload_consented(upload_url, bytes)
      uri = URI.parse(upload_url.to_s)
      raise Error, "not a Microsoft 365 upload link" unless uri.scheme == "https" && HOSTS.any? { |h| uri.host.to_s.downcase.end_with?(h) }

      response = Faraday.new(url: "#{uri.scheme}://#{uri.host}") { |f| SafeHttp.pin_faraday!(f, uri) }.put(uri.request_uri, bytes) do |req|
        req.headers["Content-Length"] = bytes.bytesize.to_s
        req.headers["Content-Range"] = "bytes 0-#{bytes.bytesize - 1}/#{bytes.bytesize}"
        req.options.timeout = 120
      end
      raise Error.new("upload failed: HTTP #{response.status}", status: response.status) unless response.success?
    rescue URI::InvalidURIError, SafeHttp::UnsafeUrl => e
      raise Error, e.message
    end

    def redirect_location(tenant_id, graph_path)
      response = graph_connection.get("#{Config.cloud[:graph]}/v1.0/#{graph_path}", nil, auth(tenant_id))
      return response.headers["Location"] if response.status.between?(300, 399) && response.headers["Location"].present?

      raise Error.new("file not reachable: HTTP #{response.status}", status: response.status)
    end

    def auth(tenant_id) = { "Authorization" => "Bearer #{TokenService.graph_token(tenant_id)}" }

    def graph_connection
      Faraday.new do |f|
        f.options.open_timeout = 5
        f.options.timeout = 60
      end
    end
  end
end
