# frozen_string_literal: true

module Insights
  # Insights business attributes that UsageStatistics::SessionKey adds to a
  # session's OTEL_RESOURCE_ATTRIBUTES.
  #
  # Only runtimes whose OpenTelemetry implementation is known to preserve custom
  # resource attributes are eligible, and only while the session's project has an
  # active Insights integration. The allowlist is intentionally closed: the
  # integration is an opt-in marker and business context, never a transport for
  # its ingest credential (or any other Integration/API token).
  module RuntimeResourceAttributes
    SUPPORTED_AGENT_TYPES = %w[claude_code codex gemini_cli kiro_cli].freeze
    INSIGHTS_KEYS = %w[user_email project_name proxy_enabled].freeze

    module_function

    def for(session)
      return {} unless SUPPORTED_AGENT_TYPES.include?(session&.agent_type)

      project = session.project
      return {} unless project && Integration.insights_for(project)

      {
        "user_email" => session.user&.email,
        "project_name" => project.name,
        "proxy_enabled" => "true"
      }.compact
    end
  end
end
