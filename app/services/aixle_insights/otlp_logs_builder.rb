# frozen_string_literal: true

module AixleInsights
  # Turns one terminal session and its llm_calls into an OTLP/JSON logs payload
  # the Insights collector accepts at POST /v1/logs.
  #
  # Shape (standard OTLP/JSON logs encoding):
  #   { resourceLogs: [ { resource: { attributes }, scopeLogs: [ { logRecords } ] } ] }
  #
  # Decisions this encodes (see design doc §Decisions):
  #   D1 — one `api_request` logRecord per LlmCall (per-call granularity).
  #   D2 — service.name is ALWAYS "claude-code" so Insights parses our tokens and
  #        cost through its ClaudeCodeEventBuilder; the real agent is carried in
  #        the `aixle.agent_type` resource attribute.
  #
  # Attribution is by resource attributes `user_email` + `project_name`: Insights
  # resolves them against the org the token selects. Both are guarded — a session
  # whose user was deleted or that has no project simply omits that attribute
  # (the event then stays unattributed in Insights rather than failing to build).
  class OtlpLogsBuilder
    SERVICE_NAME = "claude-code"
    SCOPE_NAME = "aixle.flow"
    EVENT_NAME = "api_request"

    def initialize(session)
      @session = session
    end

    # The OTLP/JSON payload hash, or nil when the session has no usage to send
    # (no llm_calls) — the caller skips an empty batch rather than POSTing one.
    def build
      calls = @session.llm_calls.order(:occurred_at).to_a
      return nil if calls.empty?

      {
        resourceLogs: [
          {
            resource: { attributes: resource_attributes },
            scopeLogs: [
              {
                scope: { name: SCOPE_NAME },
                logRecords: calls.map { |call| log_record(call) }
              }
            ]
          }
        ]
      }
    end

    private

    def resource_attributes
      attrs = [ string_attr("service.name", SERVICE_NAME) ]
      attrs << string_attr("aixle.agent_type", @session.agent_type) if @session.agent_type.present?
      attrs << string_attr("user_email", @session.user.email) if @session.user&.email.present?
      attrs << string_attr("project_name", @session.project.name) if @session.project&.name.present?
      attrs
    end

    # One Claude-shaped api_request record. The attribute names are the ones
    # Insights' ClaudeCodeEventBuilder reads; cache_creation_tokens is our
    # cache_write_tokens, and cost_usd is total_cents_precise / 100.
    def log_record(call)
      {
        timeUnixNano: time_unix_nano(call.occurred_at),
        body: { stringValue: EVENT_NAME },
        attributes: [
          string_attr("event.name", EVENT_NAME),
          string_attr("session.id", @session.id.to_s),
          string_attr("model", call.model),
          int_attr("input_tokens", call.input_tokens),
          int_attr("output_tokens", call.output_tokens),
          int_attr("cache_read_tokens", call.cache_read_tokens),
          int_attr("cache_creation_tokens", call.cache_write_tokens),
          double_attr("cost_usd", (call.total_cents_precise.to_d / 100).to_f)
        ]
      }
    end

    def string_attr(key, value)
      { key: key, value: { stringValue: value.to_s } }
    end

    def int_attr(key, value)
      { key: key, value: { intValue: value.to_i } }
    end

    def double_attr(key, value)
      { key: key, value: { doubleValue: value.to_f } }
    end

    def time_unix_nano(time)
      (time.to_r * 1_000_000_000).to_i.to_s
    end
  end
end
