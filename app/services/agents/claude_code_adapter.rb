# frozen_string_literal: true

module Agents
  # Claude Code adapter for credential handling
  # Config: ~/.claude.json
  # Docs: https://docs.anthropic.com/claude-code
  class ClaudeCodeAdapter < BaseAdapter
    CONFIG_VERSION = "2.1.14"
    METRIC_TOKENS_NAME = "claude_code.token.usage"
    METRIC_COST_NAME = "claude_code.cost.usage"
    LEGACY_METRIC_NAMES = {
      "terminal.session.tokens" => METRIC_TOKENS_NAME,
      "terminal.session.cost" => METRIC_COST_NAME
    }.freeze

    def self.default_config_paths
      [ "~/.claude/settings.json", "CLAUDE.md" ]
    end

    def config_path
      "#{home_dir}/.claude.json"
    end

    def auth_file_paths
      [
        "#{home_dir}/.claude.json",
        "#{home_dir}/.claude/.credentials.json"
      ]
    end

    # Watch both auth files — primaryApiKey lands in .claude.json (API key path),
    # claudeAiOauth lands in .claude/.credentials.json (claude.ai OAuth path).
    def auth_watch_path
      auth_file_paths.join(",")
    end

    def home_dir
      "/home/claude"
    end

    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # Built-in Claude Code tools (always allowed)
    BUILTIN_TOOLS = %w[Task Bash Glob Grep LS Read Edit MultiEdit Write WebFetch WebSearch].freeze

    def allowed_tools(mcp_server_names = [])
      mcp_permissions = mcp_server_names.map { |name| "mcp__#{name}" }
      BUILTIN_TOOLS + mcp_permissions
    end

    # Keys that indicate auth is complete (watcher uses dot-notation for nested).
    # Two real-token sources, depending on login method:
    #   - primaryApiKey                — written to ~/.claude.json after platform.claude.com (API key)
    #   - claudeAiOauth.accessToken    — written to ~/.claude/.credentials.json after claude.ai (OAuth)
    # We wait specifically for these because oauthAccount alone is just metadata
    # and lands before the token, causing a race.
    def auth_required_keys
      %w[primaryApiKey claudeAiOauth.accessToken]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      config["primaryApiKey"].present? || config.dig("claudeAiOauth", "accessToken").present?
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice(
        "oauthAccount",          # OAuth account metadata (.claude.json)
        "primaryApiKey",         # API key (.claude.json, platform.claude.com path)
        "customApiKeyResponses", # approved/rejected API keys (.claude.json)
        "userID",                # user identifier (.claude.json)
        "claudeAiOauth"          # OAuth tokens (.claude/.credentials.json, claude.ai path)
      ).compact
    end

    # Generate ~/.claude.json content. Excludes claudeAiOauth (lives in .credentials.json).
    def generate_config(credentials, workflow_config = {})
      {
        # Credentials from database (API-key path fields, OAuth account metadata, userID, etc.)
        **credentials.except("claudeAiOauth"),

        # Fixed values (skip onboarding, etc.)
        "installMethod" => "global",
        "hasCompletedOnboarding" => true,
        "lastOnboardingVersion" => CONFIG_VERSION,
        "numStartups" => 1,
        "effortCalloutV2Dismissed" => true,

        # Project config (generated based on workflow)
        "projects" => generate_projects_config(workflow_config)
      }
    end

    # Override to write multiple config files. The set depends on which auth path
    # the user used: claude.ai OAuth credentials live in a separate file.
    def config_files(credentials, workflow_config = {})
      mcp_names = workflow_config[:enabled_mcp_servers] || []
      model = workflow_config[:model]
      files = {
        # Main config (includes primaryApiKey for API-key path users)
        config_path => generate_config(credentials, workflow_config).to_json,
        # Settings with permissions and optional model override
        "#{home_dir}/.claude/settings.json" => generate_settings(mcp_names, model: model).to_json
      }

      oauth = credentials["claudeAiOauth"]
      if oauth.is_a?(Hash) && oauth["accessToken"].present?
        files["#{home_dir}/.claude/.credentials.json"] = { "claudeAiOauth" => oauth }.to_json
      end

      files
    end

    # Session command for agent terminal.
    # Both modes use full Claude TUI to preserve streamed terminal UX.
    def session_command(mode:, prompt: nil, model: nil)
      model ? "claude --model #{Shellwords.shellescape(model)}" : "claude"
    end

    # Context file: ~/.claude/CLAUDE.md (auto-read by Claude Code at startup)
    def context_file_path
      "#{home_dir}/.claude/CLAUDE.md"
    end

    def skills_agent_name
      "claude-code"
    end

    # MCP config: /workspace/.mcp.json
    # Claude Code supports: "http" (streamable-http), "sse" (deprecated), "stdio"
    # See: https://code.claude.com/docs/en/mcp
    def mcp_config(servers)
      mcp_servers = {}
      servers.each do |s|
        entry = { "type" => mcp_transport_type(s.transport) }
        if s.transport.to_s == "stdio"
          entry["command"] = s.command if s.respond_to?(:command)
          entry["args"] = s.args if s.respond_to?(:args)
          entry["env"] = s.env if s.respond_to?(:env) && s.env.present?
        else
          entry["url"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        mcp_servers[s.name] = entry
      end
      { "/workspace/.mcp.json" => { "mcpServers" => mcp_servers }.to_json }
    end

    # Fetch available models from Anthropic API.
    # Requires API key auth (OAuth accounts may not have access).
    ANTHROPIC_MODELS_URL = "https://api.anthropic.com/v1/models"

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    def fetch_available_models_with_source(credentials, credential: nil)
      api_key = credentials["primaryApiKey"]

      if api_key.present?
        models = fetch_models_via_api(api_key)
        if models != FALLBACK_CLAUDE_MODELS
          { models: models, source: :api }
        else
          { models: models, source: :fallback }
        end
      else
        { models: FALLBACK_CLAUDE_MODELS, source: :fallback }
      end
    rescue StandardError => e
      Rails.logger.warn("[ClaudeCodeAdapter] fetch_available_models failed: #{e.message}")
      { models: FALLBACK_CLAUDE_MODELS, source: :fallback }
    end

    FALLBACK_CLAUDE_MODELS = [
      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6", description: "Best balance of speed and intelligence" },
      { model_id: "claude-opus-4-6", display_name: "Claude Opus 4.6", description: "Most capable model" },
      { model_id: "claude-sonnet-4-5-20250929", display_name: "Claude Sonnet 4.5", description: "Fast and capable" },
      { model_id: "claude-opus-4-5-20251101", display_name: "Claude Opus 4.5", description: "Advanced reasoning" },
      { model_id: "claude-haiku-4-5-20251001", display_name: "Claude Haiku 4.5", description: "Fastest model" }
    ].freeze

    # Default environment variables for Claude Code runtime.
    def default_env_vars(session)
      route_token = session.route_token
      resource_attributes = "terminal_session_token=#{route_token}"

      {
        # MITM proxy — intercept Anthropic API traffic
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => "api.anthropic.com",
        # OTLP telemetry
        "CLAUDE_CODE_ENABLE_TELEMETRY" => "1",
        "OTEL_EXPORTER_OTLP_ENDPOINT" => Settings.otel.endpoint,
        "OTEL_EXPORTER_OTLP_PROTOCOL" => "http/protobuf",
        "OTEL_METRICS_EXPORTER" => "otlp",
        "OTEL_METRIC_EXPORT_INTERVAL" => "2000",
        "OTEL_RESOURCE_ATTRIBUTES" => resource_attributes
      }.compact
    end

    # Parse OTLP payload, collect events, and persist usage statistics.
    # Each OTLP batch (delta) becomes one event with token breakdown.
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
        models = all_events.filter_map { |e| e["model"] }.uniq

        stat.assign_attributes(
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

    def fetch_models_via_api(api_key)
      uri = URI(ANTHROPIC_MODELS_URL)
      uri.query = URI.encode_www_form(limit: 100)
      req = Net::HTTP::Get.new(uri)
      req["x-api-key"] = api_key
      req["anthropic-version"] = "2023-06-01"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
      return FALLBACK_CLAUDE_MODELS unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      models = (data["data"] || []).filter_map do |m|
        next unless m["id"].to_s.include?("claude")

        { model_id: m["id"], display_name: m["display_name"] || m["id"], description: "#{m["max_input_tokens"]} max input tokens" }
      end
      models.presence || FALLBACK_CLAUDE_MODELS
    end

    # Build normalized events from OTLP payload (same format as Cursor API events).
    def extract_events_from_otlp(payload, terminal_session_token)
      events = []
      return events if terminal_session_token.blank?

      (payload["resourceMetrics"] || []).each do |rm|
        resource_attrs = rm.dig("resource", "attributes") || []

        (rm["scopeMetrics"] || []).each do |sm|
          token_breakdown = {}
          cost_usd = 0.0
          model = nil
          timestamp_ns = nil

          (sm["metrics"] || []).each do |metric|
            name = normalize_metric_name(metric["name"].to_s)
            next if name.blank?

            extract_data_points(metric).each do |dp|
              token = extract_terminal_session_token(dp["attributes"] || [], resource_attrs)
              next if token != terminal_session_token

              value = number_from_data_point(dp)
              next if value.nil?

              dp_attrs = dp["attributes"] || []
              model ||= attribute_value(dp_attrs, "model")
              timestamp_ns ||= dp["timeUnixNano"]

              case name
              when METRIC_TOKENS_NAME
                type = attribute_value(dp_attrs, "type") || "unknown"
                token_breakdown[type] = (token_breakdown[type] || 0) + value.to_i
              when METRIC_COST_NAME
                cost_usd += value.to_f
              end
            end
          end

          next if token_breakdown.values.sum.zero? && cost_usd.zero?

          events << {
            "model" => model,
            "timestamp" => timestamp_ns ? (timestamp_ns.to_i / 1_000_000).to_s : nil,
            "tokenUsage" => {
              "inputTokens" => token_breakdown["input"] || 0,
              "outputTokens" => token_breakdown["output"] || 0,
              "cacheReadTokens" => token_breakdown["cacheRead"] || 0,
              "cacheWriteTokens" => token_breakdown["cacheCreation"] || 0,
              "totalCents" => (cost_usd * 100).round(6)
            },
            "source" => "otlp"
          }
        end
      end

      events
    end

    def aggregate_events(events)
      events.each_with_object(
        { input_tokens: 0, output_tokens: 0, cache_write_tokens: 0,
          cache_read_tokens: 0, total_cents: 0.0 }
      ) do |event, totals|
        usage = event["tokenUsage"] || {}
        totals[:input_tokens] += usage["inputTokens"].to_i
        totals[:output_tokens] += usage["outputTokens"].to_i
        totals[:cache_write_tokens] += usage["cacheWriteTokens"].to_i
        totals[:cache_read_tokens] += usage["cacheReadTokens"].to_i
        totals[:total_cents] += usage["totalCents"].to_f
      end
    end

    def normalize_metric_name(name)
      return name if name == METRIC_TOKENS_NAME || name == METRIC_COST_NAME

      LEGACY_METRIC_NAMES[name]
    end

    def extract_data_points(metric)
      sum = metric["sum"]
      return sum["dataPoints"] if sum.is_a?(Hash) && sum["dataPoints"].is_a?(Array)

      gauge = metric["gauge"]
      return gauge["dataPoints"] if gauge.is_a?(Hash) && gauge["dataPoints"].is_a?(Array)

      []
    end

    def extract_terminal_session_token(attrs, resource_attrs)
      value = attribute_value(attrs, "terminal_session_token")
      value ||= attribute_value(resource_attrs, "terminal_session_token")

      normalize_terminal_session_token(value)
    end

    def attribute_value(attrs, key)
      attrs.each do |kv|
        next unless kv["key"] == key

        value = kv["value"] || {}
        return value["stringValue"].to_s if value.key?("stringValue")
        return value["intValue"].to_s if value.key?("intValue")
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

    def dollars_to_cents(value)
      (value.to_f * 100).round
    end

    # Map internal transport name to Claude Code MCP type
    def mcp_transport_type(transport)
      case transport.to_s
      when "streamable-http", "http" then "http"
      when "sse"                     then "sse"
      else "stdio"
      end
    end

    def generate_settings(mcp_server_names = [], model: nil)
      settings = {
        # Auto-accept the bypass permissions warning
        "permissions" => {
          "defaultMode" => "dontAsk",
          "allow" => allowed_tools(mcp_server_names),
          "deny" => [],
          "ask" => []
        },
        "bypassPermissionsWarningAccepted" => true,
        "enableAllProjectMcpServers" => true
      }
      settings["model"] = model if model.present?
      settings
    end

    def generate_projects_config(workflow_config)
      mcp_names = workflow_config[:enabled_mcp_servers] || []
      {
        "/workspace" => {
          # Tools and MCP from workflow config
          "allowedTools" => allowed_tools(mcp_names),
          "mcpServers" => workflow_config[:mcp_servers] || {},
          "mcpContextUris" => workflow_config[:mcp_context_uris] || [],
          "enabledMcpjsonServers" => workflow_config[:enabled_mcp_servers] || [],
          "disabledMcpjsonServers" => workflow_config[:disabled_mcp_servers] || [],

          # Always trust workspace (skip dialog)
          "hasTrustDialogAccepted" => true,
          "projectOnboardingSeenCount" => 1,

          # External includes (security)
          "hasClaudeMdExternalIncludesApproved" => false,
          "hasClaudeMdExternalIncludesWarningShown" => false,

          # Vulnerability cache (will be populated at runtime)
          "reactVulnerabilityCache" => {
            "detected" => false,
            "package" => nil,
            "packageName" => nil,
            "version" => nil,
            "packageManager" => nil
          }
        }
      }
    end
  end
end
