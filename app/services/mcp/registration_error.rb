# frozen_string_literal: true

module MCP
  # Raised when RFC 7591 dynamic client registration fails: the authorization
  # server advertises no registration_endpoint, returns a non-2xx status, an
  # unparseable body, or a body without a client_id. NOT raised for an unsafe
  # registration_endpoint — that is an UnsafeUrlError so the SSRF signal is never
  # masked as a generic registration failure.
  #
  # WHY THIS CLASS CARRIES A CODE: "couldn't connect" is actively misleading for the
  # most common failure here. Vercel's authorization server, for one, answers our
  # registration with `invalid_redirect_uri` — it approves only loopback callbacks,
  # so no hosted deployment can ever self-register, and no amount of retrying or
  # network debugging will change that. The user has to be told that an operator
  # must configure a client ID instead.
  class RegistrationError < DiscoveryError
    # Ours, not upstream's: the authorization server advertised no registration
    # endpoint at all, so there was nothing to POST to.
    NO_ENDPOINT = "no_registration_endpoint"

    # RFC 7591 §3.2.2 registration error codes, plus the two generic OAuth codes an
    # authorization server realistically returns from this endpoint.
    #
    # This map IS the allowlist. An `error` value that is not a key here is dropped
    # rather than shown, which is what keeps a hostile server's prose out of our UI
    # and our logs — the value that survives is one of these fixed strings.
    MESSAGES = {
      NO_ENDPOINT =>
        "This server's authorization server does not support automatic app registration, " \
        "so an operator has to configure a client ID for it.",
      "invalid_redirect_uri" =>
        "This server's authorization server does not accept this deployment's callback URL, " \
        "so an operator has to register a client ID for it.",
      "invalid_client_metadata" =>
        "This server's authorization server rejected our client registration.",
      "invalid_software_statement" =>
        "This server's authorization server requires a signed software statement we cannot provide.",
      "unapproved_software_statement" =>
        "This server's authorization server requires a signed software statement we cannot provide.",
      "access_denied" =>
        "This server's authorization server refused to register this app.",
      "invalid_request" =>
        "This server's authorization server rejected our client registration."
    }.freeze

    # The allowlist gate: returns the code only when we recognise it, nil otherwise.
    def self.known_code(value)
      value = value.to_s
      MESSAGES.key?(value) ? value : nil
    end

    def user_message = MESSAGES.fetch(code, super())
  end
end
