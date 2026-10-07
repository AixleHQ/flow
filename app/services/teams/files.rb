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
    NETWORK_ERRORS = [ SocketError, Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse ].freeze

    module_function

    # A link SharePoint signed (a 1:1 file's downloadUrl, Graph's download
    # redirect): it needs no token. Sent byte for byte through Net::HTTP — a
    # client that re-encodes the query breaks the signature, and SharePoint
    # answers 401 (seen on staging, 2026-10-06).
    def download_link(url, max_bytes: MAX_BYTES)
      uri = microsoft_365_uri(url)
      buffer = +"".b
      SafeHttp.http_for(uri, open_timeout: 5, read_timeout: 60).start do |http|
        http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
          raise Error.new("download failed: HTTP #{response.code}", status: response.code.to_i) unless response.is_a?(Net::HTTPSuccess)

          response.read_body do |chunk|
            buffer << chunk
            raise Error, "file exceeds #{max_bytes / 1024 / 1024} MB" if buffer.bytesize > max_bytes
          end
        end
      end
      buffer
    rescue *NETWORK_ERRORS => e
      raise Error.new("download failed: #{e.message}", status: 503)
    end

    def microsoft_365_uri(url)
      uri = URI.parse(url.to_s)
      raise Error, "not a Microsoft 365 file link" unless uri.scheme == "https" && HOSTS.any? { |h| uri.host.to_s.downcase.end_with?(h) }

      SafeHttp.vetted_address(uri)
      uri
    rescue URI::InvalidURIError, SafeHttp::UnsafeUrl => e
      raise Error, e.message
    end

    # A channel or group-chat file, by the link its message's attachment named,
    # read only from the conversation's own drive: the permission behind it
    # reaches every file of the organization, and a message can name any link.
    # Graph answers with a redirect to a short-lived download link.
    def download_shared(tenant_id, content_url, allowed_drive:, max_bytes: MAX_BYTES)
      share = "u!#{Base64.urlsafe_encode64(content_url.to_s, padding: false)}"
      item = GraphClient.get(tenant_id, "shares/#{share}/driveItem", "$select" => "id,parentReference")
      drive = item.dig("parentReference", "driveId")
      raise Error, "the file is not in the conversation's own files" if allowed_drive.blank? || drive != allowed_drive

      Rails.logger.info("[Teams::Files] read tenant=#{tenant_id} drive=#{drive} item=#{item['id']}")
      location = redirect_location(tenant_id, "shares/#{share}/driveItem/content")
      download_link(location, max_bytes: max_bytes)
    end

    # Where a team keeps its channels' files.
    def channel_drive(conversation)
      channel_folder(conversation).dig("parentReference", "driveId")
    end

    # Where a group chat's files live: the OneDrive of the person who sent them.
    def user_drive(tenant_id, object_id)
      return nil unless object_id.to_s.match?(Config::GUID)

      GraphClient.get(tenant_id, "users/#{object_id}/drive", "$select" => "id")["id"]
    end

    def channel_folder(conversation)
      GraphClient.get(conversation.tenant_id, "teams/#{Messages.escape(Messages.group_id(conversation))}/channels/" \
                                              "#{Messages.escape(conversation.external_id)}/filesFolder")
    end

    # An image pasted into a message, stored with the message itself.
    def download_hosted(tenant_id, graph_path, max_bytes: MAX_BYTES)
      response = graph_get(tenant_id, graph_path)
      raise Error.new("hosted content: HTTP #{response.status}", status: response.status) unless response.success?
      raise Error, "file exceeds #{max_bytes / 1024 / 1024} MB" if response.body.bytesize > max_bytes

      response.body
    end

    # Into a channel's own files, under Aixle/; the name is made unique there.
    def upload_to_channel(conversation, filename, bytes)
      raise Error, "#{filename} is larger than #{MAX_UPLOAD_BYTES / 1024 / 1024} MB" if bytes.bytesize > MAX_UPLOAD_BYTES

      tenant = conversation.tenant_id
      folder = channel_folder(conversation)
      drive = folder.dig("parentReference", "driveId")
      path = "drives/#{Messages.escape(drive)}/items/#{Messages.escape(folder['id'])}:/Aixle/#{ERB::Util.url_encode(filename)}:/content"
      item = GraphClient.request(tenant, :put, path, query: { "@microsoft.graph.conflictBehavior" => "rename" }, body: bytes,
                                                     headers: { "Content-Type" => "application/octet-stream" })
      Rails.logger.info("[Teams::Files] wrote tenant=#{tenant} drive=#{drive} item=#{item['id']}")
      item
    end

    # Where the bytes go after a person accepted a file consent card.
    # Also a signed link, so also sent byte for byte.
    def upload_consented(upload_url, bytes)
      uri = microsoft_365_uri(upload_url)
      request = Net::HTTP::Put.new(uri.request_uri)
      request["Content-Length"] = bytes.bytesize.to_s
      request["Content-Range"] = "bytes 0-#{bytes.bytesize - 1}/#{bytes.bytesize}"
      request.body = bytes
      response = SafeHttp.http_for(uri, open_timeout: 5, read_timeout: 120).start { |http| http.request(request) }
      raise Error.new("upload failed: HTTP #{response.code}", status: response.code.to_i) unless response.is_a?(Net::HTTPSuccess)
    rescue *NETWORK_ERRORS => e
      raise Error.new("upload failed: #{e.message}", status: 503)
    end

    def redirect_location(tenant_id, graph_path)
      response = graph_get(tenant_id, graph_path)
      return response.headers["Location"] if response.status.between?(300, 399) && response.headers["Location"].present?

      raise Error.new("file not reachable: HTTP #{response.status}", status: response.status)
    end

    def auth(tenant_id) = { "Authorization" => "Bearer #{TokenService.graph_token(tenant_id)}" }

    def graph_get(tenant_id, graph_path)
      graph_connection.get("#{Config.cloud[:graph]}/v1.0/#{graph_path}", nil, auth(tenant_id))
    rescue Faraday::Error => e
      raise Error.new("Graph GET #{graph_path}: #{e.message}", status: 503)
    end

    def graph_connection
      Faraday.new do |f|
        f.options.open_timeout = 5
        f.options.timeout = 60
      end
    end
  end
end
