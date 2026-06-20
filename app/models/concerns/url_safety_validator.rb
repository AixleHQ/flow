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

  module_function

  # Returns an array of human-readable error messages for the given URL.
  # An empty array means the URL passes all safety checks.
  # Pass `require_https: true` to reject plain `http://` URLs.
  def errors_for(url, require_https: false)
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
    errors << "cannot point to private or internal network addresses" if private_or_loopback?(host)

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

    ip = IPAddr.new(host)
    ip.private? || ip.loopback? || ip.link_local?
  rescue IPAddr::InvalidAddressError
    resolved_to_private?(host)
  end

  def resolved_to_private?(hostname)
    Resolv.getaddresses(hostname).any? do |addr|
      ip = IPAddr.new(addr)
      ip.private? || ip.loopback? || ip.link_local?
    end
  rescue Resolv::ResolvError
    false
  end
end
