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
    # Stamped in the session's metadata by the launch that handed the key out. A session
    # without it was launched before keys existed and is still trusted by token alone.
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

    def required_for?(session)
      session.metadata.is_a?(Hash) && session.metadata[LAUNCH_MARKER].present?
    end

    def secret
      Rails.application.key_generator.generate_key(PURPOSE, 32)
    end
  end
end
