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

    def resource_attributes(session)
      token = session&.route_token
      return if token.blank?

      "terminal_session_token=#{token},#{ATTRIBUTE}=#{generate(token)}"
    end

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
