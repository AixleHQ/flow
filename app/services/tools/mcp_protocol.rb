# frozen_string_literal: true

require "mcp"
require "stringio"

module Tools
  # Protocol-version negotiation for the /mcp endpoint, shared by both servers
  # behind it (session-scoped and personal).
  #
  # The mcp gem advertises every version in
  # `MCP::Configuration::SUPPORTED_STABLE_PROTOCOL_VERSIONS` — 2026-07-28
  # included — and its `initialize` handler agrees to whichever of them the
  # client offered. Its result bodies, however, are the 2025-11-25 shapes:
  # 2026-07-28 makes `resultType` mandatory on *every* result and
  # `cacheScope` + `ttlMs` mandatory on the cacheable ones (`tools/list`,
  # `prompts/list`, `resources/list`, `resources/read`), and the gem emits
  # none of them. A client that offers 2026-07-28 — Claude Code always does —
  # therefore agrees on a version this server does not speak, and its strict
  # validation drops every list response, so no tools are ever registered.
  #
  # Until the gem implements those result shapes, the endpoint negotiates down
  # to the newest version it genuinely serves. The offer is rewritten on the
  # way in rather than the agreed version on the way out, so the whole
  # handshake stays the gem's (capabilities, serverInfo and instructions are
  # all version-dependent), and the `MCP-Protocol-Version` header the client
  # sends on every subsequent request stays consistent with what it was given.
  module MCPProtocol
    # The newest protocol version the gem's result bodies conform to.
    MAX_NEGOTIABLE_VERSION = "2025-11-25"

    # Offers we can honor as-is: everything the gem supports that is not newer
    # than what we actually serve. Anything else negotiates down to the max.
    NEGOTIABLE_VERSIONS = MCP::Configuration::SUPPORTED_STABLE_PROTOCOL_VERSIONS
      .select { |version| version <= MAX_NEGOTIABLE_VERSION }
      .freeze

    class << self
      # Caps the `protocolVersion` an `initialize` request offers, rewriting
      # the Rack body in place so the gem can only agree to a version it
      # serves. A missing or non-String version is left untouched: the gem
      # answers that with the invalid-params error the spec asks for.
      def clamp_initialize_offer!(request)
        return unless request.post?

        body = parsed_body(request)
        return unless body.is_a?(Hash) && body["method"] == "initialize"

        params = body["params"]
        return unless params.is_a?(Hash)

        offered = params["protocolVersion"]
        return unless offered.is_a?(String)
        return if NEGOTIABLE_VERSIONS.include?(offered)

        params["protocolVersion"] = MAX_NEGOTIABLE_VERSION
        rewrite_body(request, body.to_json)
      end

      private

      def parsed_body(request)
        raw = request.body.read
        request.body.rewind
        JSON.parse(raw)
      rescue JSON::ParserError, TypeError
        nil
      end

      # `RAW_POST_DATA` as well as `rack.input`: Rails caches the raw body
      # there as soon as anything reads the request parameters (request
      # logging does), and `ActionDispatch::Request#body` prefers that cache —
      # replacing only the stream would leave the original offer in play.
      def rewrite_body(request, json)
        request.env["RAW_POST_DATA"] = json
        request.env["rack.input"] = StringIO.new(json)
        request.env["CONTENT_LENGTH"] = json.bytesize.to_s
      end
    end
  end
end
