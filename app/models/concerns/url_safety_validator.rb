# frozen_string_literal: true

# Shared URL safety validation. Rejects URLs whose scheme is not http/https,
# whose host is on the BLOCKED_HOSTS list, or whose host resolves to a private,
# loopback, or link-local address.
#
# Use as a standalone helper from services or model validators:
#
#   errors = UrlSafetyValidator.errors_for(some_url)
#   raise SomeError, errors.first if errors.any?
#
# Or call individual predicates:
#
#   UrlSafetyValidator.safe?(url)
#   UrlSafetyValidator.private_or_loopback?("10.0.0.1")
module UrlSafetyValidator
  BLOCKED_HOSTS = %w[
    localhost
    metadata.google.internal
    metadata.goog
  ].freeze

  PUBLIC_DNS_NAMESERVERS = %w[1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4].freeze
  PUBLIC_DNS_TIMEOUTS = [ 2, 4 ].freeze

  module_function

  # Returns an array of human-readable error messages for the given URL.
  # An empty array means the URL passes all safety checks.
  # Pass `require_https: true` to reject plain `http://` URLs.
  # Pass `trusted_hosts_override:` to extend the trusted-host allowlist for
  # a single call-site without weakening global URL validation.
  def errors_for(url, require_https: false, trusted_hosts_override: nil)
    raw = url.to_s
    return [ "is required" ] if raw.blank?

    uri = safe_parse(raw)
    return [ "is not a valid URL" ] if uri.nil?

    errors = []
    if require_https
      errors << "must use https" unless uri.scheme == "https"
    else
      errors << "must use http or https" unless allowed_scheme?(uri)
    end

    host = uri.host.to_s.downcase
    errors << "cannot point to internal services" if BLOCKED_HOSTS.include?(host)
    errors << "cannot point to private or internal network addresses" if blocked_address?(host, trusted_hosts_override: trusted_hosts_override)

    errors
  end

  def safe?(url)
    errors_for(url).empty?
  end

  def safe_parse(url)
    URI.parse(url.to_s)
  rescue URI::InvalidURIError
    nil
  end

  def allowed_scheme?(uri)
    %w[http https].include?(uri.scheme)
  end

  def private_or_loopback?(host)
    return false if host.to_s.empty?

    literal = ip_or_nil(host)
    return blocked_ip?(literal) unless literal.nil?

    resolves_to_blocked?(host)
  end

  # True when the host should be rejected as private/internal.
  #
  # Literal-IP hosts are always checked. For hostnames, the resolution check is
  # skipped when the host appears in `trusted_hosts` — this handles split-horizon
  # DNS where a public hostname (e.g. `coder.staging.aixle.com`) resolves to a
  # private IP from inside the cluster.
  def blocked_address?(host, trusted_hosts_override: nil)
    return false if host.to_s.empty?

    literal = ip_or_nil(host)
    return blocked_ip?(literal) unless literal.nil?

    return false if trusted_host?(host, trusted_hosts_override: trusted_hosts_override)

    resolves_to_blocked?(host)
  end

  def trusted_host?(host, trusted_hosts_override: nil)
    trusted_hosts(trusted_hosts_override).include?(host.to_s.downcase)
  end

  def trusted_hosts(extra_hosts = nil)
    raw = Settings.respond_to?(:url_safety) ? Settings.url_safety&.trusted_hosts : nil
    Array(raw).concat(Array(extra_hosts)).map { |h| h.to_s.downcase.strip }.reject(&:empty?).uniq
  end

  # Parse a host as an IP literal, or nil when it is not a well-formed IPAddr.
  # NOTE: IPAddr rejects libc-numeric forms (decimal/hex/octal-packed IPv4 such
  # as "2852039166" or "0x7f.0.0.1"); those deliberately fall through to
  # #resolves_to_blocked?, which resolves them with the SAME libc resolver the
  # HTTP client uses at connect time.
  def ip_or_nil(host)
    IPAddr.new(host.to_s)
  rescue IPAddr::InvalidAddressError
    nil
  end

  # A resolved/literal IP that must never be dialed server-side: RFC1918 private,
  # loopback, link-local (incl. the 169.254.169.254 cloud-metadata address), or
  # the unspecified address (0.0.0.0 / ::, which the OS routes to loopback).
  def blocked_ip?(ip)
    ip.private? || ip.loopback? || ip.link_local? || ip.to_i.zero?
  end

  # Resolve `host` EXACTLY as Net::HTTP will at connect time (libc getaddrinfo)
  # and reject if ANY resulting address is blocked. This closes the SSRF gap
  # where IPAddr/Resolv miss packed-numeric hosts (e.g. "2852039166" =>
  # 169.254.169.254) that glibc's getaddrinfo happily connects to. An
  # unresolvable host yields [] (not blocked — the connection would fail anyway).
  def resolves_to_blocked?(host)
    resolve_addresses(host).any? { |ip| blocked_ip?(ip) }
  end

  def resolve_addresses(host)
    Addrinfo.getaddrinfo(host, nil, nil, :STREAM).filter_map do |info|
      IPAddr.new(info.ip_address.split("%").first)
    rescue IPAddr::InvalidAddressError
      nil
    end
  rescue StandardError
    []
  end

  # Resolve a hostname using public DNS resolvers (Cloudflare/Google) and
  # return the first IPv4 address that is not private/loopback/link-local.
  # Used by integrations that must reach a public hostname from inside a
  # cluster whose internal resolver returns a private/unreachable address
  # via split-horizon DNS. Returns nil when no public IPv4 can be found.
  def resolve_public_ipv4(host)
    return nil if host.to_s.empty?

    Resolv::DNS.open(nameserver: PUBLIC_DNS_NAMESERVERS) do |dns|
      dns.timeouts = PUBLIC_DNS_TIMEOUTS
      dns.getresources(host, Resolv::DNS::Resource::IN::A).each do |record|
        ip_str = record.address.to_s
        addr = IPAddr.new(ip_str)
        return ip_str unless addr.private? || addr.loopback? || addr.link_local?
      end
    end
    nil
  rescue StandardError
    nil
  end
end
