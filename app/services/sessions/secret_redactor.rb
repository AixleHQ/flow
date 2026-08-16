# frozen_string_literal: true

module Sessions
  # Replaces known secret values with a stable fingerprint before a log is
  # stored or served.
  #
  # A value handed to an agent through `get_config_item` necessarily enters the
  # model's context, and from there the provider request body — which the MITM
  # logger captures in full (`docker/base/logger/mitm_logger.py`). It also lands
  # in `/tmp/terminal_output.log` the moment the agent echoes it. "In context but
  # not in logs" is therefore only achievable as value-level redaction at each
  # sink, never as "do not log this tool".
  #
  # The set is KNOWN and enumerable — the `secret` config items attached to the
  # session — so this is not a heuristic scan for secret-looking text. Everything
  # else in a log is returned verbatim, which is what
  # `spec-session-observability-mcp-tools.md` promised and this narrows.
  #
  # WHAT THIS DOES NOT COVER, deliberately: the tmux `pipe-pane` dual sink
  # (`docker/base/entrypoint.sh`) writes to the pod's stdout at print time, so a
  # printed secret reaches the cluster log stack minutes before any collector
  # runs here. Product decision 2026-08-17: keep the sink, state the limit. See
  # docs/implementation-artifacts/spec-session-config-item-access.md.
  class SecretRedactor
    # No length floor. ContextLog::MIN_REDACT_LEN exists because that path
    # registers every MCP header/env value, including non-secrets like "json"
    # and "true", whose masking would only obscure the log. Here every value is
    # a config item somebody marked `secret` — a four-character one is still a
    # secret, and a floor would silently exempt it.
    def self.for_session(session)
      new(secret_values_for(session))
    end

    def self.secret_values_for(session)
      return [] if session.nil?

      ids = SessionConfigResolver.new(session).resolve_config_item_ids
      return [] if ids.blank?

      ConfigItem.where(id: ids).with_item_type(:secret).filter_map(&:decrypted_value)
    rescue StandardError => e
      # A redactor that raises would take the whole log-collection step with it
      # and lose the log entirely. Failing closed here means "no redaction", so
      # say so loudly rather than silently storing raw bytes.
      Rails.logger.error("[SecretRedactor] Failed to resolve session secrets: #{e.message}")
      []
    end

    def initialize(values)
      # Longest-first so a secret that is a substring of a longer one never
      # corrupts the longer replacement.
      @values = Array(values).map(&:to_s).reject(&:blank?).uniq.sort_by { |v| -v.length }
    end

    def any?
      @values.any?
    end

    # Returns `text` unchanged when there is nothing to redact, so the common
    # case (a session with no secrets) costs one predicate.
    def call(text)
      return text if text.blank? || @values.empty?

      str = text.to_s
      @values.each { |value| str = str.gsub(value, fingerprint(value)) }
      str
    end

    private

    # Same shape ContextLog has used since the OAuth work, so one grep finds
    # every redaction in a collected artifact regardless of which sink wrote it.
    def fingerprint(value)
      "«redacted:sha256:#{Digest::SHA256.hexdigest(value)[0, 8]}»"
    end
  end
end
