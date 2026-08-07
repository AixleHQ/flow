# frozen_string_literal: true

module MCP
  # Raised by the single SSRF choke point (OauthDiscoveryService#guard!) whenever
  # UrlSafetyValidator rejects a URL: plain http (require_https), a blocked host, a
  # literal or DNS-resolved private/loopback/link-local address, or a redirect hop
  # that lands on any of the above. Every outbound URL in the discovery flow is
  # attacker-influenced (pasted MCP url, WWW-Authenticate header, RFC 9728/8414/7591
  # JSON, DCR echoes), so this is the security-critical failure mode.
  class UnsafeUrlError < DiscoveryError
    # Says that we refused, without saying which url or what about it was rejected —
    # a probe must not be able to read our network topology out of an alert.
    def user_message = "This server's address, or one it redirected to, is not allowed."
  end
end
