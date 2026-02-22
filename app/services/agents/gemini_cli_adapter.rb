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
    METRIC_COST_NAME = "gemini_cli.cost.usage"
    LOG_EVENT_NAME = "gemini_cli.api_response"
    LEGACY_METRIC_NAMES = {
      "terminal.session.tokens" => METRIC_TOKENS_NAME,
      "terminal.session.cost" => METRIC_COST_NAME
    }.freeze

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
      new_events = extract_events_from_otlp(payload, terminal_session.route_token)
      return :accepted if new_events.empty?

      UsageStatistic.transaction do
        stat = terminal_session.usage_statistic || terminal_session.build_usage_statistic(
          tokens: 0, cost_cents: 0, input_tokens: 0, output_tokens: 0,
          cache_write_tokens: 0, cache_read_tokens: 0, source: "otlp",
          events_count: 0, events_data: []
        )

        all_events = (stat.events_data || []) + new_events
        totals = aggregate_events(all_events)
        models = all_events.filter_map { |event| event["model"] }.uniq

        stat.assign_attributes(
          tokens: totals[:input_tokens] + totals[:output_tokens] + totals[:cache_write_tokens] + totals[:cache_read_tokens],
          input_tokens: totals[:input_tokens],
          output_tokens: totals[:output_tokens],
          cache_write_tokens: totals[:cache_write_tokens],
          cache_read_tokens: totals[:cache_read_tokens],
          total_cents_precise: totals[:total_cents],
          cost_cents: totals[:total_cents].ceil,
          models: models,
          source: "otlp",
          events_count: all_events.size,
          events_data: all_events
        )
        stat.save!
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

    def extract_events_from_otlp(payload, terminal_session_token)
      return [] if terminal_session_token.blank?

      metric_events = extract_events_from_otlp_metrics(payload, terminal_session_token)
      return metric_events unless metric_events.empty?

      extract_events_from_otlp_logs(payload, terminal_session_token)
    end

    def extract_events_from_otlp_metrics(payload, terminal_session_token)
      events = []

      resource_metrics = payload["resourceMetrics"] || []
      resource_metrics.each do |resource_metric|
        resource_attrs = resource_metric.dig("resource", "attributes") || []
        scope_metrics = resource_metric["scopeMetrics"] || []

        scope_metrics.each do |scope_metric|
          token_breakdown = {}
          cost_usd = 0.0
          model = nil
          timestamp_ns = nil

          metrics = scope_metric["metrics"] || []
          metrics.each do |metric|
            name = normalize_metric_name(metric["name"].to_s)
            next if name.blank?

            data_points = extract_data_points(metric)
            data_points.each do |data_point|
              token_value = extract_terminal_session_token(data_point["attributes"] || [], resource_attrs)
              next if token_value != terminal_session_token

              value = number_from_data_point(data_point)
              next if value.nil?

              dp_attrs = data_point["attributes"] || []
              model ||= extract_model(dp_attrs)
              timestamp_ns ||= data_point["timeUnixNano"]

              case name
              when METRIC_TOKENS_NAME
                token_type = normalize_token_type(attribute_string(dp_attrs, "type") || attribute_string(dp_attrs, "token_type"))
                token_breakdown[token_type] = (token_breakdown[token_type] || 0) + value.to_i
              when METRIC_COST_NAME
                cost_usd += value.to_f
              end
            end
          end

          next if token_breakdown.values.sum.zero? && cost_usd.zero?

          events << build_usage_event(
            model: model,
            timestamp_ns: timestamp_ns,
            input_tokens: token_breakdown["input"] || 0,
            output_tokens: token_breakdown["output"] || 0,
            cache_read_tokens: token_breakdown["cacheRead"] || 0,
            cache_write_tokens: token_breakdown["cacheCreation"] || 0,
            total_cents: (cost_usd * 100).round(6)
          )
        end
      end

      events
    end

    def extract_events_from_otlp_logs(payload, terminal_session_token)
      events = []

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

            input_tokens = attribute_number(attrs, "input_token_count").to_i
            output_tokens = attribute_number(attrs, "output_token_count").to_i
            cache_read_tokens = attribute_number(attrs, "cached_content_token_count").to_i
            # Gemini logs can include internal "thoughts/tool" buckets; treat as output-like generated tokens.
            output_tokens += attribute_number(attrs, "thoughts_token_count").to_i
            output_tokens += attribute_number(attrs, "tool_token_count").to_i
            total_cents = log_cost_cents(attrs)

            next if input_tokens.zero? && output_tokens.zero? && cache_read_tokens.zero? && total_cents.zero?

            events << build_usage_event(
              model: extract_model(attrs),
              timestamp_ns: log_record["timeUnixNano"],
              input_tokens: input_tokens,
              output_tokens: output_tokens,
              cache_read_tokens: cache_read_tokens,
              cache_write_tokens: 0,
              total_cents: total_cents
            )
          end
        end
      end

      events
    end

    def aggregate_events(events)
      events.each_with_object(
        { input_tokens: 0, output_tokens: 0, cache_write_tokens: 0, cache_read_tokens: 0, total_cents: 0.0 }
      ) do |event, totals|
        usage = event["tokenUsage"] || {}
        totals[:input_tokens] += usage["inputTokens"].to_i
        totals[:output_tokens] += usage["outputTokens"].to_i
        totals[:cache_write_tokens] += usage["cacheWriteTokens"].to_i
        totals[:cache_read_tokens] += usage["cacheReadTokens"].to_i
        totals[:total_cents] += usage["totalCents"].to_f
      end
    end

    def build_usage_event(model:, timestamp_ns:, input_tokens:, output_tokens:, cache_read_tokens:, cache_write_tokens:, total_cents:)
      {
        "model" => model,
        "timestamp" => timestamp_ns ? (timestamp_ns.to_i / 1_000_000).to_s : nil,
        "tokenUsage" => {
          "inputTokens" => input_tokens,
          "outputTokens" => output_tokens,
          "cacheReadTokens" => cache_read_tokens,
          "cacheWriteTokens" => cache_write_tokens,
          "totalCents" => total_cents.to_f
        },
        "source" => "otlp"
      }
    end

    def normalize_metric_name(name)
      return name if name == METRIC_TOKENS_NAME || name == METRIC_COST_NAME

      LEGACY_METRIC_NAMES[name]
    end

    def normalize_token_type(raw_type)
      case raw_type.to_s
      when "input", "prompt", "promptTokens", "input_token_count" then "input"
      when "output", "completion", "completionTokens", "output_token_count" then "output"
      when "cacheRead", "cache_read", "cached_content", "cached_content_token_count" then "cacheRead"
      when "cacheCreation", "cacheWrite", "cache_write", "cache_write_token_count" then "cacheCreation"
      else raw_type.to_s
      end
    end

    def extract_model(attrs)
      attribute_string(attrs, "model") || attribute_string(attrs, "model_id")
    end

    def log_cost_cents(attrs)
      cents = attribute_number(attrs, "cost_cents")
      return cents.to_f if cents.present?

      usd = attribute_number(attrs, "cost_usd")
      return (usd * 100).round(6) if usd.present?

      0.0
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
