# frozen_string_literal: true

module MCP
  # Raised when RFC 7591 dynamic client registration fails: the authorization
  # server advertises no registration_endpoint, returns a non-2xx status, an
  # unparseable body, or a body without a client_id. NOT raised for an unsafe
  # registration_endpoint — that is an UnsafeUrlError so the SSRF signal is never
  # masked as a generic registration failure.
  class RegistrationError < DiscoveryError; end
end
