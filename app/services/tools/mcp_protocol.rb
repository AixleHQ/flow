# frozen_string_literal: true

require "mcp"
require "stringio"

module Tools
  # Protocol-version negotiation for the /mcp endpoint, shared by both servers
  # behind it (session-scoped and personal).
  #
  # The mcp gem's result bodies are the 2025-11-25 shapes, but it advertises
  # 2026-07-28 as negotiable. That version makes `resultType` mandatory on
  # *every* result (SEP-2322) and `cacheScope` + `ttlMs` mandatory on the
  # cacheable ones (SEP-2549: `tools/list`, `prompts/list`, `resources/list`,
  # `resources/read`), and the gem emits neither over the legacy `initialize`
  # handshake — its README says so outright: "Servers on stable protocol
  # versions never send `resultType`". A client that offers 2026-07-28 — Claude
  # Code always does — therefore agrees on a version this server does not
  # speak, its strict validation drops every list response, and no tools are
  # ever registered. So the endpoint negotiates down to the newest version it
  # genuinely serves.
  #
  # == What the gem supports natively, and what it does not
  #
  # `MCP::Configuration#protocol_version` (README, "Server Protocol Version")
  # is the documented way to state which version a server speaks, and it is
  # what `configuration` below hands to both servers. It cannot carry the whole
  # fix: `MCP::Server#init` consults it only as a *fallback* for an offer
  # outside `SUPPORTED_STABLE_PROTOCOL_VERSIONS`, and echoes back any offer
  # inside it — so a server configured for 2025-11-25 still agrees to
  # 2026-07-28 when a client offers it. Nothing else in 1.1.0 (the newest
  # release) reaches that decision: `define_custom_method` raises for methods
  # the gem already handles, `initialize` among them; there is no
  # handler-registration hook for `initialize` or the list methods; and
  # `around_request` only receives the instrumentation-data hash, not the
  # params or the result. Serving 2026-07-28 properly instead is equally out of
  # reach — `ttl_ms:`/`cache_scope:` are public constructor kwargs, but
  # `resultType` has no public seam at all.
  #
  # That leaves one gap to cover here: an offer the gem would echo but cannot
  # serve (`UNSERVED_VERSIONS`). `clamp_initialize_offer!` rewrites those on
  # the way in — the offer, rather than the agreed version on the way out, so
  # the handshake stays entirely the gem's (capabilities, `serverInfo` and
  # `instructions` are all version-dependent) and the `MCP-Protocol-Version`
  # header the client sends on every subsequent request stays consistent with
  # what it was handed.
  #
  # == Where this ideally belongs
  #
  # Upstream, in the gem: `Server#init` should cap the negotiated version at
  # `configuration.protocol_version` rather than treat it as a fallback, or the
  # gem should emit the 2026-07-28 result shapes on the legacy wire too. In
  # modelcontextprotocol/ruby-sdk, #476 (merged, shipped in 1.1.0) is what made
  # 2026-07-28 negotiable through `initialize`; #487 (merged, unreleased)
  # stamps `resultType` only when a modern SEP-2575 `_meta` envelope is present
  # and deliberately leaves legacy results unstamped; #499 (open) does the same
  # for the cache hints. A gem upgrade alone therefore will not fix a
  # legacy-handshake client such as Claude Code, and this module stays until
  # negotiation itself can be capped through configuration — at which point
  # `clamp_initialize_offer!` goes away and `MAX_NEGOTIABLE_VERSION` is the one
  # value left to move.
  module MCPProtocol
    # The newest protocol version the gem's result bodies conform to.
    MAX_NEGOTIABLE_VERSION = "2025-11-25"

    # Offers we can honor as-is: everything the gem supports that is not newer
    # than what we actually serve.
    NEGOTIABLE_VERSIONS = MCP::Configuration::SUPPORTED_STABLE_PROTOCOL_VERSIONS
      .select { |version| version <= MAX_NEGOTIABLE_VERSION }
      .freeze

    # ...and the ones it would agree to but cannot serve. Anything outside both
    # lists is unknown to the gem and settled by `configuration` instead.
    UNSERVED_VERSIONS = (MCP::Configuration::SUPPORTED_STABLE_PROTOCOL_VERSIONS - NEGOTIABLE_VERSIONS).freeze

    class << self
      # Both servers are built with this. It pins the version the gem reports
      # for an offer it does not recognize — its own default there is the
      # latest stable, 2026-07-28, which it cannot serve.
      def configuration
        MCP::Configuration.new(protocol_version: MAX_NEGOTIABLE_VERSION)
      end

      # Caps the `protocolVersion` an `initialize` request offers, rewriting
      # the Rack body in place so the gem can only agree to a version it
      # serves. Only the offers it would echo but not serve are touched: a
      # version it does serve is left alone, an unrecognized one is settled by
      # `configuration`, and a missing or non-String one is left for the gem to
      # answer with the invalid-params error the spec asks for.
      def clamp_initialize_offer!(request)
        return unless request.post?

        body = parsed_body(request)
        return unless body.is_a?(Hash) && body["method"] == "initialize"

        params = body["params"]
        return unless params.is_a?(Hash)
        return unless UNSERVED_VERSIONS.include?(params["protocolVersion"])

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
