# frozen_string_literal: true

module UsageStatistics
  # Proof that an OTLP batch came from the session it names.
  #
  # A batch identifies its session by `terminal_session_token` — the route token, which
  # also sits in every terminal URL and is broadcast to the whole company — so on its
  # own it let anyone who had seen a URL write tokens and cost into that session. The
  # container is now handed a second resource attribute, this key, derived from the
  # route token and never stored; the ingest recomputes it.
  #
  # It rides in OTEL_RESOURCE_ATTRIBUTES next to the token rather than in an exporter
  # header: that variable is already proven to survive every runtime's SDK and the
  # otlp-ingest relay, which forwards the body and drops the headers.
  module SessionKey
    PURPOSE = "usage-ingest"
    ATTRIBUTE = "terminal_session_key"
    # Stamped in the session's metadata by the launch that handed the key out
    # (AgentBaseStrategy). Still written for observability, but no longer gates
    # whether a key is required — see #required_for?.
    LAUNCH_MARKER = "usage_key"

    module_function

    def generate(route_token)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{PURPOSE}:#{route_token}")
    end

    def valid?(route_token, candidate)
      return false if route_token.blank? || candidate.blank?

      ActiveSupport::SecurityUtils.secure_compare(generate(route_token), candidate.to_s)
    end

    INTERNAL_KEYS = [ "terminal_session_token", ATTRIBUTE, "agent_type" ].freeze

    # The session's OTEL_RESOURCE_ATTRIBUTES: the internal routing pair every
    # usage batch must carry, plus Insights business attributes when the runtime
    # and the project's active Insights integration allow them.
    def resource_attributes(session)
      token = session&.route_token
      return if token.blank?

      attributes = {
        "terminal_session_token" => token,
        ATTRIBUTE => generate(token),
        "agent_type" => session.agent_type
      }.merge(Insights::RuntimeResourceAttributes.for(session))

      serialize(attributes)
    end

    def serialize(attributes)
      (INTERNAL_KEYS + Insights::RuntimeResourceAttributes::INSIGHTS_KEYS).filter_map do |key|
        value = attributes[key]
        "#{key}=#{escape(value)}" unless value.blank?
      end.join(",")
    end
    private_class_method :serialize

    # Bytes allowed unencoded: the W3C baggage-octet range the OTel resource
    # spec references (printable ASCII minus space, `"`, `,`, `;`, `\`), minus
    # `=` and `%` so values round-trip. Everything else — Unicode, comma, equals,
    # backslash, whitespace — is percent-encoded per UTF-8 byte.
    #
    # Encoding stays minimal on purpose: the Rust SDK used by Codex and Kiro CLI
    # does not percent-decode, so plain values (emails, ASCII project names) must
    # reach the collector byte-for-byte.
    UNENCODED_BYTES = "\\x21\\x23\\x24\\x26-\\x2B\\x2D-\\x3A\\x3C\\x3E-\\x5B\\x5D-\\x7E"
    ENCODED_BYTE = Regexp.new("[^#{UNENCODED_BYTES}]".b, Regexp::NOENCODING)

    def escape(value)
      value.to_s.b.gsub(ENCODED_BYTE) { |byte| format("%%%02X", byte.ord) }.force_encoding(Encoding::UTF_8)
    end
    private_class_method :escape

    # Every usage batch must prove it came from the session it names — no
    # exception. A pre-key "grandfather" clause once trusted sessions launched
    # before keys existed by route_token alone; but the route_token is in every
    # terminal URL and is broadcast company-wide, so over the (publicly reachable)
    # ingest endpoint anyone who had seen a URL could forge token and cost into
    # that session's usage. Every live launch has stamped the key since keys
    # shipped, so the clause only widened the attack surface for no live benefit.
    def required_for?(_session)
      true
    end

    def secret
      Rails.application.key_generator.generate_key(PURPOSE, 32)
    end
  end
end
