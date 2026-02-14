# frozen_string_literal: true

module Agents
  # Google Gemini CLI adapter for credential handling
  # Gemini CLI requires GOOGLE_CLOUD_PROJECT environment variable BEFORE starting
  #
  # Config structure (discovered from container):
  #   ~/.gemini/oauth_creds.json - OAuth tokens (access_token, refresh_token, etc.)
  #   ~/.gemini/settings.json - Auth settings (selectedType: oauth-personal)
  #   ~/.gemini/google_accounts.json - Account info
  class GeminiCliAdapter < BaseAdapter
    METRIC_TOKENS_NAME = "gemini_cli.token.usage"
    LOG_EVENT_NAME = "gemini_cli.api_response"

    def self.default_config_paths
      [ "~/.gemini/settings.json", "GEMINI.md" ]
    end

    def config_path
      "#{home_dir}/.gemini/oauth_creds.json"
    end

    def home_dir
      "/home/gemini"
    end

    def auth_required_keys
      %w[refresh_token]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      config["refresh_token"].present?
    end

    def extract_credentials(config_content)
      config = parse_json(config_content)
      # Extract OAuth credentials
      config.slice("access_token", "refresh_token", "scope", "token_type", "id_token", "expiry_date")
    end

    def generate_config(credentials, workflow_config = {})
      # Return OAuth credentials as-is for oauth_creds.json
      credentials
    end

    # Multiple config files needed for Gemini CLI
    def config_files(credentials, workflow_config = {})
      {
        # OAuth credentials
        "#{home_dir}/.gemini/oauth_creds.json" => credentials.to_json,
        # Settings per https://geminicli.com/docs/get-started/configuration/
        "#{home_dir}/.gemini/settings.json" => generate_settings.to_json
      }
    end

    # Session command: gemini --yolo (interactive), gemini -p (non-interactive)
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file
    def session_command(mode:, prompt: nil)
      if mode == "non_interactive" && prompt.present?
        "gemini -p"
      else
        "gemini --yolo"
      end
    end

    # Context file: ~/.gemini/GEMINI.md (auto-read by Gemini CLI at startup)
    def context_file_path
      "#{home_dir}/.gemini/GEMINI.md"
    end

    # Skill files: appended as sections to ~/.gemini/GEMINI.md (user-scoped, not in workspace)
    def skill_files(skills)
      sections = skills.filter_map do |skill|
        next if skill.content.blank?

        "## Skill: #{skill.title || skill.name}\n\n#{skill.content}"
      end
      return {} if sections.empty?

      { "#{home_dir}/.gemini/GEMINI.md" => "\n\n" + sections.join("\n\n---\n\n") + "\n" }
    end

    def skill_merge_strategy
      :append
    end

    # MCP config: merged into ~/.gemini/settings.json
    def mcp_config(servers)
      mcp_servers = {}
      servers.each do |s|
        entry = { "trust" => true }
        entry["httpUrl"] = s.url if s.url.present?
        entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        mcp_servers[s.name] = entry
      end
      { "#{home_dir}/.gemini/settings.json" => { "mcpServers" => mcp_servers }.to_json }
    end

    def mcp_merge_strategy
      :merge_json
    end

    # Directories to mount as tmpfs for credential storage
    def tmpfs_paths
      [
        "#{home_dir}/.gemini",    # Gemini CLI config
        "#{home_dir}/.mitmproxy"  # MITM proxy CA certificates
      ]
    end

    # =================================================================
    # Environment Variables (from session/credential metadata)
    # =================================================================

    # Fields that must be configured before starting container
    def required_env_fields
      [
        { key: "google_cloud_project", label: "Google Cloud Project ID", required: true, placeholder: "my-project-123" }
      ]
    end

    # Convert metadata to environment variables for container
    def env_vars_from_metadata(metadata)
      {
        "GOOGLE_CLOUD_PROJECT" => metadata["google_cloud_project"]
      }.compact
    end

    # Default environment variables for Gemini CLI runtime.
    def default_env_vars(session)
      route_token = session.route_token
      resource_attributes = "terminal_session_token=#{route_token}"

      {
        "OTEL_RESOURCE_ATTRIBUTES" => resource_attributes
      }.compact
    end

    # Parse OTLP payload and persist usage statistics for a terminal session.
    def ingest_usage(payload, terminal_session)
      totals = extract_usage_from_otlp(payload, terminal_session.route_token)
      return :accepted if totals[:tokens].zero? && totals[:cost_cents].zero?

      UsageStatistic.transaction do
        usage = terminal_session.usage_statistic || terminal_session.build_usage_statistic(tokens: 0, cost_cents: 0)
        usage.tokens += totals[:tokens]
        usage.cost_cents += totals[:cost_cents]
        usage.save!
      end

      :ok
    end

    private

    def generate_settings
      {
        # Authentication
        "security" => {
          "auth" => {
            "selectedType" => "oauth-personal"
          },
          # Don't ask for folder trust in containers
          "folderTrust" => {
            "enabled" => false
          }
        },
        # General settings
        "general" => {
          "previewFeatures" => true,       # Enable preview models (gemini-3-*)
          "vimMode" => false,
          "enableAutoUpdate" => false,     # Disable auto-update in containers
          "enableAutoUpdateNotification" => false
        },
        # UI settings for headless/container environment
        "ui" => {
          "hideBanner" => true,
          "hideTips" => true,
          "hideWindowTitle" => true,
          "dynamicWindowTitle" => false,
          "showHomeDirectoryWarning" => false
        },
        # Privacy
        "privacy" => {
          "usageStatisticsEnabled" => true  # Allow telemetry in containers
        },
        # Telemetry (OpenTelemetry)
        "telemetry" => {
          "enabled" => true,
          "target" => "local",
          "otlpEndpoint" => Settings.otel.metrics_endpoint,
          "otlpProtocol" => "http",
          "logPrompts" => false
        },
        # Tools - auto approve all operations (container is the sandbox)
        "tools" => {
          "autoAccept" => true,
          "approvalMode" => "auto_edit",          # Auto-approve ALL tools
          "sandbox" => false,                # Container is already sandboxed
          "useRipgrep" => true
        },
        # Experimental features
        "experimental" => {
          "useOSC52Paste" => true,           # Better paste in web terminal
          "enableAgents" => true             # Enable subagents
        }
      }
    end

    def extract_usage_from_otlp(payload, terminal_session_token)
      usage = { tokens: 0, cost_cents: 0 }
      return usage if terminal_session_token.blank?

      usage[:tokens] += extract_usage_from_otlp_metrics(payload, terminal_session_token)
      if usage[:tokens].zero?
        usage[:tokens] += extract_usage_from_otlp_logs(payload, terminal_session_token)
      end

      usage
    end

    def extract_usage_from_otlp_metrics(payload, terminal_session_token)
      total = 0

      resource_metrics = payload["resourceMetrics"] || []
      resource_metrics.each do |resource_metric|
        resource_attrs = resource_metric.dig("resource", "attributes") || []
        scope_metrics = resource_metric["scopeMetrics"] || []

        scope_metrics.each do |scope_metric|
          metrics = scope_metric["metrics"] || []
          metrics.each do |metric|
            next unless metric["name"].to_s == METRIC_TOKENS_NAME

            data_points = extract_data_points(metric)
            data_points.each do |data_point|
              token_value = extract_terminal_session_token(data_point["attributes"] || [], resource_attrs)
              next if token_value != terminal_session_token

              value = number_from_data_point(data_point)
              next if value.nil?

              total += value.to_i
            end
          end
        end
      end

      total
    end

    def extract_usage_from_otlp_logs(payload, terminal_session_token)
      total = 0

      resource_logs = payload["resourceLogs"] || []
      resource_logs.each do |resource_log|
        resource_attrs = resource_log.dig("resource", "attributes") || []
        scope_logs = resource_log["scopeLogs"] || []

        scope_logs.each do |scope_log|
          log_records = scope_log["logRecords"] || []
          log_records.each do |log_record|
            attrs = log_record["attributes"] || []
            token_value = extract_terminal_session_token(attrs, resource_attrs)
            next if token_value != terminal_session_token

            event_name = attribute_string(attrs, "event.name")
            next unless event_name == LOG_EVENT_NAME

            total += sum_token_attributes(attrs)
          end
        end
      end

      total
    end

    def sum_token_attributes(attrs)
      keys = %w[
        input_token_count
        output_token_count
        cached_content_token_count
        thoughts_token_count
        tool_token_count
      ]

      keys.sum { |key| attribute_number(attrs, key).to_i }
    end

    def extract_data_points(metric)
      sum = metric["sum"]
      return sum["dataPoints"] if sum.is_a?(Hash) && sum["dataPoints"].is_a?(Array)

      gauge = metric["gauge"]
      return gauge["dataPoints"] if gauge.is_a?(Hash) && gauge["dataPoints"].is_a?(Array)

      []
    end

    def extract_terminal_session_token(attrs, resource_attrs)
      value = attribute_string(attrs, "terminal_session_token")
      value ||= attribute_string(resource_attrs, "terminal_session_token")

      normalize_terminal_session_token(value)
    end

    def attribute_string(attrs, key)
      attrs.each do |kv|
        next unless kv["key"] == key

        value = kv["value"] || {}
        return value["stringValue"].to_s if value.key?("stringValue")
        return value["intValue"].to_s if value.key?("intValue")
        return value["doubleValue"].to_s if value.key?("doubleValue")
      end

      nil
    end

    def attribute_number(attrs, key)
      attrs.each do |kv|
        next unless kv["key"] == key

        value = kv["value"] || {}
        return value["intValue"].to_f if value.key?("intValue")
        return value["doubleValue"].to_f if value.key?("doubleValue")
        return value["stringValue"].to_f if value.key?("stringValue")
      end

      nil
    end

    def normalize_terminal_session_token(raw)
      token = raw.to_s.strip
      return nil if token.blank?

      token
    end

    def number_from_data_point(data_point)
      if data_point.key?("asInt")
        data_point["asInt"].to_f
      elsif data_point.key?("asDouble")
        data_point["asDouble"].to_f
      end
    end
  end
end
