# frozen_string_literal: true

require "net/http"

# The one way to open a connection to a URL that a user, or a remote server, chose.
#
# It resolves the host once, refuses it when any address it resolves to must not be
# dialed (UrlSafetyValidator#blocked_ip?), and then connects to the address it
# checked. A check that resolves the name and a client that resolves it again are
# two answers, and a DNS server that gives a public address to the first and a
# private one to the second (rebinding) walks straight through the check.
#
# TLS still verifies the hostname: Net::HTTP keeps the name for SNI and the
# certificate, and only the socket goes to the pinned address.
module SafeHttp
  class UnsafeUrl < StandardError; end

  module_function

  # A Net::HTTP for `uri`, not yet started, bound to the vetted address.
  def http_for(uri, open_timeout:, read_timeout:, trusted_hosts: [])
    ip = vetted_address(uri, trusted_hosts: trusted_hosts)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = ip if ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    http
  end

  # Pins a Faraday connection built for `uri` (in a Faraday.new block) the same way.
  def pin_faraday!(faraday, uri, trusted_hosts: [])
    ip = vetted_address(uri, trusted_hosts: trusted_hosts)
    faraday.adapter(:net_http) { |http| http.ipaddr = ip if ip }
  end

  # The address to dial, or nil for a host the call site trusts to resolve through
  # internal DNS. Raises UnsafeUrl when the URL may not be dialed at all.
  def vetted_address(uri, trusted_hosts: [])
    raise UnsafeUrl, "must use http or https" unless %w[http https].include?(uri.scheme)

    host = uri.host.to_s.downcase
    raise UnsafeUrl, "cannot point to internal services" if host.empty? || UrlSafetyValidator::BLOCKED_HOSTS.include?(host)

    literal = UrlSafetyValidator.ip_or_nil(host)
    if literal
      raise UnsafeUrl, "cannot point to private or internal network addresses" if UrlSafetyValidator.blocked_ip?(literal)

      return literal.to_s
    end
    return nil if UrlSafetyValidator.trusted_hosts(trusted_hosts).include?(host)

    addresses = UrlSafetyValidator.resolved_addresses(host)
    raise UnsafeUrl, "does not resolve" if addresses.empty?
    if addresses.any? { |ip| UrlSafetyValidator.blocked_ip?(ip) }
      raise UnsafeUrl, "cannot point to private or internal network addresses"
    end

    addresses.first.to_s
  end
end
