# frozen_string_literal: true

module MCPAuth
  # A client identified by URL (draft-ietf-oauth-client-id-metadata-document):
  # its client_id is an https URL, and the JSON document served there is its
  # registration. Claude, Claude Code and VS Code identify themselves this way.
  #
  # The URL is chosen by whoever starts the authorization, so it is fetched like
  # any other hostile URL: through SafeHttp, no redirects, a short timeout, a
  # capped body.
  class ClientMetadataDocument
    TIMEOUT = 5
    MAX_BYTES = 16.kilobytes
    CACHE_TTL = 10.minutes

    def self.url?(client_id) = client_id.to_s.start_with?("https://")

    def self.fetch(url)
      document = Rails.cache.fetch([ "mcp-auth/cimd", Digest::SHA256.hexdigest(url) ], expires_in: CACHE_TTL) do
        new(url).fetch
      end
      Client.new(client_id: url, kind: "cimd", name: document["client_name"], host: URI(url).host,
                 redirect_uris: document["redirect_uris"])
    end

    def initialize(url)
      @url = url
    end

    # The parts of the document we use, validated; raises InvalidClient.
    def fetch
      uri = validated_uri
      document = parse(request(uri))
      unless document["client_id"] == @url
        raise InvalidClient, "The app's metadata document names a different client"
      end

      redirect_uris = document["redirect_uris"]
      unless redirect_uris.is_a?(Array) && redirect_uris.any? && redirect_uris.all?(String)
        raise InvalidClient, "The app's metadata document lists no redirect URIs"
      end

      { "client_name" => document["client_name"].is_a?(String) ? document["client_name"].squish.truncate(100) : nil,
        "redirect_uris" => redirect_uris.first(MCPAuthClient::MAX_REDIRECT_URIS) }
    end

    private

    def validated_uri
      uri = URI.parse(@url)
      unless uri.scheme == "https" && uri.host.present? && uri.userinfo.nil? && uri.fragment.nil? &&
             uri.path.present? && uri.path != "/" && uri.path.split("/").exclude?("..")
        raise InvalidClient, "The app's client ID is not a valid metadata document URL"
      end

      uri
    rescue URI::InvalidURIError
      raise InvalidClient, "The app's client ID is not a valid metadata document URL"
    end

    def request(uri)
      http = SafeHttp.http_for(uri, open_timeout: TIMEOUT, read_timeout: TIMEOUT)
      get = Net::HTTP::Get.new(uri)
      get["Accept"] = "application/json"
      get["User-Agent"] = "AixleFlow-MCP-OAuth"
      body = +""
      status = nil
      http.request(get) do |response|
        status = response.code.to_i
        response.read_body do |chunk|
          body << chunk
          raise InvalidClient, "The app's metadata document is too large" if body.bytesize > MAX_BYTES
        end
      end
      raise InvalidClient, "The app's metadata document could not be loaded (HTTP #{status})" unless status == 200

      body
    rescue SafeHttp::UnsafeUrl
      raise InvalidClient, "The app's metadata document is on an address Aixle does not connect to"
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError, IOError
      raise InvalidClient, "The app's metadata document could not be loaded"
    end

    def parse(body)
      document = JSON.parse(body)
      raise InvalidClient, "The app's metadata document is not a JSON object" unless document.is_a?(Hash)

      document
    rescue JSON::ParserError
      raise InvalidClient, "The app's metadata document is not valid JSON"
    end
  end
end
