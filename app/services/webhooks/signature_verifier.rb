# frozen_string_literal: true

module Webhooks
  # Per-source inbound webhook verification. Each provider signs differently, so
  # verification is a strategy keyed by WebhookEndpoint#verification_strategy —
  # NOT a single "HMAC" code path. All comparisons are constant-time and run on
  # the RAW request body (signatures are byte-sensitive).
  class SignatureVerifier
    Result = Struct.new(:ok, :reason, keyword_init: true) do
      def ok? = ok
    end

    DEFAULT_TOLERANCE = 300 # seconds (Slack/Stripe replay window)

    def self.verify(strategy:, secret:, request:, raw_body:, tolerance: DEFAULT_TOLERANCE, now: Time.current)
      new(strategy: strategy, secret: secret, request: request, raw_body: raw_body,
          tolerance: tolerance, now: now).verify
    end

    def initialize(strategy:, secret:, request:, raw_body:, tolerance:, now:)
      @strategy = strategy.to_s
      @secret = secret.to_s
      @request = request
      @raw_body = raw_body.to_s
      @tolerance = tolerance
      @now = now
    end

    def verify
      case @strategy
      when "none"          then ok
      when "slack_v0"      then verify_slack_v0
      when "hmac_sha256"   then verify_hmac_sha256
      when "shared_token"  then verify_shared_token
      else
        fail_with("unknown verification strategy: #{@strategy}")
      end
    end

    private

    def verify_slack_v0
      return fail_with("missing secret") if @secret.blank?

      timestamp = header("X-Slack-Request-Timestamp")
      signature = header("X-Slack-Signature")
      return fail_with("missing slack headers") if timestamp.blank? || signature.blank?

      ts = timestamp.to_i
      return fail_with("stale timestamp") if (@now.to_i - ts).abs > @tolerance

      base = "v0:#{timestamp}:#{@raw_body}"
      expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', @secret, base)}"
      secure_eq?(signature, expected) ? ok : fail_with("signature mismatch")
    end

    def verify_hmac_sha256
      return fail_with("missing secret") if @secret.blank?

      header_name = config_header || "X-Hub-Signature-256"
      provided = header(header_name)
      return fail_with("missing signature header") if provided.blank?

      digest = OpenSSL::HMAC.hexdigest("SHA256", @secret, @raw_body)
      candidates = [ digest, "sha256=#{digest}" ]
      candidates.any? { |c| secure_eq?(provided, c) } ? ok : fail_with("signature mismatch")
    end

    def verify_shared_token
      return fail_with("missing secret") if @secret.blank?

      header_name = config_header || "X-Webhook-Token"
      provided = header(header_name)
      return fail_with("missing token") if provided.blank?

      secure_eq?(provided, @secret) ? ok : fail_with("token mismatch")
    end

    def header(name)
      @request.headers[name]
    end

    # Optional per-endpoint override of the signature/token header name.
    def config_header
      nil
    end

    def secure_eq?(left, right)
      ActiveSupport::SecurityUtils.secure_compare(left.to_s, right.to_s)
    rescue ArgumentError
      false # different lengths
    end

    def ok = Result.new(ok: true, reason: nil)
    def fail_with(reason) = Result.new(ok: false, reason: reason)
  end
end
