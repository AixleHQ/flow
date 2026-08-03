# frozen_string_literal: true

module MCP
  # Asks an MCP server what tools it declares, and fingerprints the answer.
  #
  # This is the app-owned seam over the `mcp` gem's client: nothing else in the
  # app talks to MCP::Client, so tests stub THIS rather than the vendored gem
  # (testing doctrine R2), and a gem API change lands in one file.
  #
  # ============================ WHY FINGERPRINTS ============================
  # A tool's DESCRIPTION is what the model reads to decide how to use it, which
  # makes it the payload in a tool-poisoning or rug-pull attack: ship a benign
  # catalogue, get approved, then swap in a description carrying instructions.
  # OWASP tracks this as MCP03:2025. Clients cannot be relied on to notice —
  # `notifications/tools/list_changed` is unimplemented or ignored in shipping
  # agents (claude-code#13646, #38324, codex#10105) — so detection is ours.
  #
  # Descriptions and schemas are hashed rather than stored: the snapshot exists
  # to answer "did this change?", and a digest answers that without keeping a
  # copy of text an attacker controls anywhere it might later be rendered.
  #
  # ============================ WHAT IS NOT PROBED ============================
  # stdio servers. Probing one means EXECUTING the package on our infrastructure,
  # which the platform deliberately does not do — packages run inside the agent
  # container, never here. Such servers report :unsupported, and the UI must say
  # so rather than implying a check happened.
  class ToolListProbe
    CONNECT_TIMEOUT = 10

    # status:
    #   :ok           — tools listed
    #   :unsupported  — stdio; cannot be probed without executing code here
    #   :unauthorized — server needs credentials this caller does not have
    #   :error        — unreachable, refused, or malformed
    Result = Struct.new(:status, :tools, :error, keyword_init: true) do
      def ok? = status == :ok
      def probed? = status == :ok
    end

    def self.call(...) = new(...).call

    # @param server [MCPServer]
    # @param access_token [String, nil] bearer token for oauth-backed servers
    def initialize(server:, access_token: nil)
      @server = server
      @access_token = access_token
    end

    def call
      return unsupported if @server.transport_stdio?
      return failure("Server has no URL") if @server.url.blank?
      return failure(url_errors.join(", ")) if url_errors.any?
      return unauthorized if needs_token_but_has_none?

      Result.new(status: :ok, tools: fingerprint(list_tools))
    rescue StandardError => e
      # An MCP server that needs a token answers 401, which the SDK surfaces as
      # an unauthorized request error. That is a fact about the server, not a
      # failure of ours — the installer reads it to decide the server needs an
      # OAuth connection rather than leaving it configured as public. Every other
      # error is just an error.
      #
      # Classified here rather than in its own rescue clause: re-raising from one
      # clause escapes the whole method, and the sibling clause never sees it.
      if e.is_a?(::MCP::Client::RequestHandlerError) && e.message.match?(/unauthorized/i)
        unauthorized("the server requires authentication")
      else
        Rails.logger.warn("[ToolListProbe] #{@server.id} (#{@server.name}): #{e.class}: #{e.message}")
        failure("#{e.class}: #{e.message}")
      end
    end

    private

    def list_tools
      transport = ::MCP::Client::HTTP.new(url: @server.url, headers: request_headers)
      client = ::MCP::Client.new(transport: transport)
      client.tools
    end

    # Stored headers carry the server's own auth (static tokens, API keys); an
    # OAuth server instead gets the caller's bearer token.
    def request_headers
      headers = (@server.headers || {}).dup
      headers["Authorization"] = "Bearer #{@access_token}" if @access_token.present?
      headers
    end

    # name + digests of the two attacker-controllable surfaces. Sorted so the
    # comparison is order-independent: a server reordering its tool list is not
    # drift.
    def fingerprint(tools)
      Array(tools).map { |tool|
        {
          "name" => tool.name.to_s,
          "description_digest" => digest(tool.description),
          "schema_digest" => digest(tool.input_schema)
        }
      }.sort_by { |t| t["name"] }
    end

    def digest(value)
      return nil if value.nil?

      Digest::SHA256.hexdigest(value.is_a?(String) ? value : value.to_json)
    end

    # The URL was validated when the server was saved, but it is user-supplied
    # and re-validated before every outbound request — the same doctrine
    # MCP::OauthDiscoveryService follows, for the same reason: this process makes
    # the request, so an internal address here is an SSRF against us.
    def url_errors
      @url_errors ||= UrlSafetyValidator.errors_for(@server.url, require_https: @server.oauth?)
    end

    def needs_token_but_has_none?
      @server.oauth? && @access_token.blank?
    end

    def unsupported
      Result.new(status: :unsupported, tools: [], error: "stdio servers run in the agent container and are not probed here")
    end

    def unauthorized(reason = "no access token available for this server")
      Result.new(status: :unauthorized, tools: [], error: reason)
    end

    def failure(message)
      Result.new(status: :error, tools: [], error: message)
    end
  end
end
