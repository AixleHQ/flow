# frozen_string_literal: true

require "base64"

module Agents
  # OpenAI Codex CLI adapter for credential handling
  # Config: ~/.codex/auth.json + ~/.codex/config.toml
  # Auth: OAuth via OpenAI (Google login)
  class CodexAdapter < BaseAdapter
    # Latest model target for migration prompt suppression.
    # Codex CLI checks: model_migrations[current_user_model] == target_model
    # Update this slug when OpenAI releases a new default model.
    LATEST_TARGET_MODEL = "gpt-5.4"

    def self.default_config_paths
      [ "~/.codex/config.toml", "AGENTS.md" ]
    end

    def config_path
      "#{home_dir}/.codex/auth.json"
    end

    def home_dir
      "/home/codex"
    end

    # Keys that indicate auth is complete
    def auth_required_keys
      %w[tokens]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      tokens = config["tokens"]
      return false unless tokens.is_a?(Hash)

      # Auth complete if we have access_token or refresh_token
      tokens["access_token"].present? || tokens["refresh_token"].present?
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice(
        "tokens",         # OAuth tokens (access, refresh, id)
        "OPENAI_API_KEY", # API key if set
        "account_id",     # Account identifier
        "last_refresh"    # Last token refresh time
      ).compact
    end

    # Generate auth.json config for a new container
    def generate_config(credentials, workflow_config = {})
      {
        **credentials,
        "last_refresh" => credentials["last_refresh"] || Time.current.iso8601
      }
    end

    # Override to write multiple config files
    def config_files(credentials, workflow_config = {})
      {
        # Auth credentials
        config_path => generate_config(credentials, workflow_config).to_json,
        # Project trust config (skip trust dialog)
        "#{home_dir}/.codex/config.toml" => generate_config_toml(workflow_config)
      }
    end

    # Config files needed before auth starts (config.toml with file-based credential store)
    def auth_setup_files
      { "#{home_dir}/.codex/config.toml" => generate_config_toml({}) }
    end

    # Session command: always codex --yolo
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file.
    def session_command(mode:, prompt: nil, model: nil)
      model_flag = model ? " --model #{Shellwords.shellescape(model)}" : ""
      "codex#{model_flag} --yolo"
    end

    # Context file: /workspace/AGENTS.md (auto-read by Codex from workspace root)
    def context_file_path
      "/workspace/AGENTS.md"
    end

    def skills_agent_name
      "codex"
    end

    # MCP config: appended to ~/.codex/config.toml
    # Codex format per https://developers.openai.com/codex/mcp/
    # - STDIO: command, args, env
    # - Streamable HTTP: url, http_headers, bearer_token_env_var
    # Type inferred by Codex from presence of url vs command — no "type" field
    def mcp_config(servers)
      sections = servers.map do |s|
        lines = []
        lines << "[mcp_servers.\"#{s.name}\"]"
        if s.transport.to_s == "stdio"
          lines << "command = \"#{s.command}\"" if s.respond_to?(:command)
          if s.respond_to?(:args) && s.args.present?
            args_toml = s.args.map { |a| "\"#{a}\"" }.join(", ")
            lines << "args = [#{args_toml}]"
          end
          if s.respond_to?(:env) && s.env.present?
            env_pairs = s.env.map { |k, v| "\"#{k}\" = \"#{v}\"" }.join(", ")
            lines << "env = { #{env_pairs} }"
          end
        else
          lines << "url = \"#{s.url}\"" if s.url.present?
          if s.headers.present? && s.headers.any?
            header_pairs = s.headers.map { |k, v| "\"#{k}\" = \"#{v}\"" }.join(", ")
            lines << "http_headers = { #{header_pairs} }"
          end
        end
        lines.join("\n")
      end
      { "#{home_dir}/.codex/config.toml" => "# MCP Servers (auto-generated)\n#{sections.join("\n\n")}\n" }
    end

    def mcp_merge_strategy
      :append_toml
    end

    # Fetch available models from Codex API.
    # When an AgentCredential record is passed via `credential:`, expired
    # access tokens are automatically refreshed using the stored refresh_token.
    CODEX_MODELS_URL = "https://chatgpt.com/backend-api/codex/models"
    CODEX_CLIENT_VERSION = "0.116.0"

    def fetch_available_models(credentials, credential: nil)
      access_token = credentials.dig("tokens", "access_token")
      return [] if access_token.blank?

      response = request_models(access_token)

      if response.code == "401" && credential
        new_token = refresh_access_token!(credential)
        return [] unless new_token

        response = request_models(new_token)
      end

      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      (data["models"] || []).filter_map do |m|
        next unless m["visibility"] == "list"

        { model_id: m["slug"], display_name: m["display_name"] || m["slug"], description: m["description"].to_s.truncate(120) }
      end
    rescue StandardError => e
      Rails.logger.warn("[CodexAdapter] fetch_available_models failed: #{e.message}")
      []
    end

    # Refresh an expired access token using the stored refresh_token.
    # Persists new tokens back to the AgentCredential record.
    # Returns the new access_token on success, nil on failure.
    OAUTH_TOKEN_URL = "https://auth.openai.com/oauth/token"
    OAUTH_CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"

    def refresh_access_token!(credential)
      refresh_token = credential.config_data.dig("tokens", "refresh_token")
      return nil if refresh_token.blank?

      uri = URI(OAUTH_TOKEN_URL)
      body = URI.encode_www_form(
        grant_type: "refresh_token",
        client_id: OAUTH_CLIENT_ID,
        refresh_token: refresh_token
      )
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = body

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[CodexAdapter] Token refresh failed: #{response.code} #{response.body.to_s.truncate(200)}")
        return nil
      end

      data = JSON.parse(response.body)
      new_tokens = credential.config_data["tokens"].merge(
        "access_token" => data["access_token"],
        "refresh_token" => data["refresh_token"],
        "id_token" => data["id_token"]
      ).compact

      new_config = credential.config_data.merge("tokens" => new_tokens, "last_refresh" => Time.current.iso8601)
      credential.update!(config_data: new_config)
      Rails.logger.info("[CodexAdapter] Access token refreshed for credential #{credential.id}")

      data["access_token"]
    rescue StandardError => e
      Rails.logger.warn("[CodexAdapter] Token refresh error: #{e.class}: #{e.message}")
      nil
    end

    # Default environment variables for Codex CLI runtime.
    # MITM_TRACKED_DOMAINS limits logging to chatgpt.com (Codex API host).
    def default_env_vars(session)
      {
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => "chatgpt.com",
        "OTEL_RESOURCE_ATTRIBUTES" => "terminal_session_token=#{session.route_token}"
      }
    end

    # Log files to collect from container after session ends.
    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # OTLP log event names emitted by Codex CLI with token counts.
    LOG_SSE_EVENT = "codex.sse_event"

    # Parse OTLP payload (logs) and persist usage statistics incrementally.
    # Called by UsageStatisticsService on each incoming OTLP batch.
    def ingest_usage(payload, terminal_session)
      new_events = extract_events_from_otlp_logs(payload, terminal_session.route_token)
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

    # Collect usage from MITM log at session cleanup (fallback).
    # Skipped if real-time OTLP ingest already populated usage.
    #
    # Fallback strategies (tried in order):
    #   1. OTLP metrics captured by MITM: Codex sends `codex.turn.token_usage`
    #      histograms to ab.chatgpt.com — extracted from MITM request bodies.
    #   2. HTTP response body (legacy): parse /codex/responses 200 responses for
    #      `response.completed` JSON with `usage` object (pre-WebSocket protocol).
    def collect_usage(terminal_session, artifacts = {})
      if terminal_session.usage_statistic.present?
        Rails.logger.info("[CodexAdapter] Session #{terminal_session.id}: usage already collected via OTLP ingest, skipping MITM fallback")
        return
      end

      mitm_log = artifacts["logs/http.log"]

      log_lines = (mitm_log || "").lines.size
      Rails.logger.info("[CodexAdapter] Session #{terminal_session.id}: MITM log #{mitm_log.present? ? "#{mitm_log.bytesize}B, #{log_lines} lines" : 'EMPTY'}")

      events = extract_events_from_otlp_metrics(mitm_log)

      if events.empty?
        events = extract_events_from_mitm(mitm_log)
      end

      if events.empty?
        Rails.logger.warn("[CodexAdapter] No usage events in MITM log for session #{terminal_session.id}")
        return
      end

      persist_usage_statistic(terminal_session, events)
    end

    private

    def request_models(access_token)
      uri = URI("#{CODEX_MODELS_URL}?client_version=#{CODEX_CLIENT_VERSION}")
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
    end

    CODEX_RESPONSES_PATH = "/backend-api/codex/responses"
    OTLP_METRICS_PATH = "/otlp/v1/metrics"
    TOKEN_USAGE_METRIC = "codex.turn.token_usage"

    # =========================================================================
    # OTLP Metrics Extraction (primary — Codex CLI ≥ 0.116)
    # =========================================================================

    # Codex CLI emits `codex.turn.token_usage` histograms via OTLP to ab.chatgpt.com.
    # MITM proxy captures these as request entries with JSON OTLP payloads.
    # aggregationTemporality=1 (DELTA) → sum across all batches per token_type.
    def extract_events_from_otlp_metrics(log_content)
      return [] if log_content.blank?

      totals = Hash.new(0.0)
      model = nil
      timestamp = nil
      batches_found = 0

      log_content.each_line do |line|
        entry = JSON.parse(line.strip)
        next unless entry["direction"] == "request"
        next unless entry["path"]&.include?("otlp/v1/metrics")

        body_text = decode_body(entry)
        next if body_text.blank?

        payload = JSON.parse(body_text)
        found = extract_otlp_token_totals(payload, totals)
        if found
          batches_found += 1
          timestamp ||= entry["ts"]
          model ||= extract_otlp_model(payload)
        end
      rescue JSON::ParserError
        next
      end

      return [] if batches_found.zero?

      Rails.logger.info(
        "[CodexAdapter] OTLP metrics: #{batches_found} batches, " \
        "in=#{totals["input"].to_i} out=#{totals["output"].to_i} " \
        "cached=#{totals["cached_input"].to_i} reasoning=#{totals["reasoning_output"].to_i} " \
        "model=#{model}"
      )

      [ {
        "model" => model,
        "timestamp" => timestamp,
        "tokenUsage" => {
          "inputTokens" => totals["input"].to_i,
          "outputTokens" => totals["output"].to_i,
          "cacheReadTokens" => totals["cached_input"].to_i,
          "cacheWriteTokens" => 0,
          "reasoningTokens" => totals["reasoning_output"].to_i,
          "totalCents" => 0.0
        },
        "source" => "otlp_metrics"
      } ]
    end

    # Sum histogram dataPoint sums for codex.turn.token_usage.
    # Returns true if any token_usage data points were found.
    def extract_otlp_token_totals(payload, totals)
      found = false
      (payload["resourceMetrics"] || []).each do |rm|
        (rm["scopeMetrics"] || []).each do |sm|
          (sm["metrics"] || []).each do |m|
            next unless m["name"] == TOKEN_USAGE_METRIC
            (m.dig("histogram", "dataPoints") || []).each do |dp|
              token_type = otlp_attr(dp["attributes"], "token_type")
              next unless token_type
              totals[token_type] += dp["sum"].to_f
              found = true
            end
          end
        end
      end
      found
    end

    def extract_otlp_model(payload)
      (payload["resourceMetrics"] || []).each do |rm|
        (rm["scopeMetrics"] || []).each do |sm|
          (sm["metrics"] || []).each do |m|
            next unless m["name"] == TOKEN_USAGE_METRIC
            (m.dig("histogram", "dataPoints") || []).each do |dp|
              model = otlp_attr(dp["attributes"], "model")
              return model if model.present?
            end
          end
        end
      end
      nil
    end

    def otlp_attr(attrs, key)
      (attrs || []).each do |a|
        return a.dig("value", "stringValue") if a["key"] == key
      end
      nil
    end

    def otlp_number(attrs, key)
      (attrs || []).each do |a|
        next unless a["key"] == key
        v = a["value"] || {}
        return v["intValue"].to_f if v.key?("intValue")
        return v["doubleValue"].to_f if v.key?("doubleValue")
        return v["stringValue"].to_f if v.key?("stringValue")
      end
      nil
    end

    # =========================================================================
    # OTLP Log Events (real-time — Codex OTEL exporter → otlp-ingest)
    # =========================================================================

    # Extract usage events from OTLP log payloads sent by Codex CLI.
    # Codex emits `codex.sse_event` logs with token counts per completion.
    def extract_events_from_otlp_logs(payload, terminal_session_token)
      events = []
      return events if terminal_session_token.blank?

      (payload["resourceLogs"] || []).each do |rl|
        resource_attrs = rl.dig("resource", "attributes") || []
        (rl["scopeLogs"] || []).each do |sl|
          (sl["logRecords"] || []).each do |lr|
            attrs = lr["attributes"] || []

            token = otlp_attr(attrs, "terminal_session_token") ||
                    otlp_attr(resource_attrs, "terminal_session_token")
            next if token != terminal_session_token

            event_name = otlp_attr(attrs, "event.name") || lr["severityText"]
            next unless event_name == LOG_SSE_EVENT

            input_tokens = otlp_number(attrs, "input_token_count").to_i
            output_tokens = otlp_number(attrs, "output_token_count").to_i
            cached_tokens = otlp_number(attrs, "cached_token_count").to_i
            reasoning_tokens = otlp_number(attrs, "reasoning_token_count").to_i
            model = otlp_attr(attrs, "model")

            next if input_tokens.zero? && output_tokens.zero?

            events << {
              "model" => model,
              "timestamp" => lr["timeUnixNano"] ? (lr["timeUnixNano"].to_i / 1_000_000).to_s : nil,
              "tokenUsage" => {
                "inputTokens" => input_tokens,
                "outputTokens" => output_tokens,
                "cacheReadTokens" => cached_tokens,
                "cacheWriteTokens" => 0,
                "reasoningTokens" => reasoning_tokens,
                "totalCents" => 0.0
              },
              "source" => "otlp"
            }
          end
        end
      end

      events
    end

    # =========================================================================
    # HTTP Response Body Parsing (legacy — pre-WebSocket protocol)
    # =========================================================================

    # Parse MITM log and extract usage from /codex/responses HTTP 200 response bodies.
    # This was the primary method when Codex used chunked NDJSON over HTTP.
    def extract_events_from_mitm(log_content)
      events = []

      (log_content || "").each_line do |line|
        entry = JSON.parse(line.strip)
        next unless entry["direction"] == "response"
        next unless entry["path"]&.start_with?(CODEX_RESPONSES_PATH)
        next unless entry["status_code"] == 200

        text = decode_body(entry)
        next if text.blank?

        event = extract_usage_from_response_body(text, entry["ts"])
        events << event if event
      rescue JSON::ParserError
        next
      end

      events
    end

    # Decode MITM log body: base64 → text, or pass through if already text.
    def decode_body(entry)
      body = entry["body"].to_s
      return "" if body.blank?

      if entry["body_encoding"] == "base64"
        Base64.decode64(body).force_encoding("UTF-8")
      else
        body
      end
    rescue ArgumentError
      ""
    end

    # Extract usage data from the tail of a chunked Responses API body.
    #
    # The response.completed JSON can be >32KB (includes tool definitions),
    # so our tail buffer may cut off the beginning. We regex-extract:
    #   - "usage":{...} — token counts (always near the end)
    #   - "model":"..." — model name (may be truncated away)
    def extract_usage_from_response_body(text, timestamp)
      usage_match = text.match(
        /"usage"\s*:\s*\{[^}]*"input_tokens"\s*:\s*(\d+).*?"output_tokens"\s*:\s*(\d+).*?"total_tokens"\s*:\s*(\d+)\s*\}/m
      )
      return nil unless usage_match

      input_tokens = usage_match[1].to_i
      output_tokens = usage_match[2].to_i

      cached_match = text.match(/"cached_tokens"\s*:\s*(\d+)/)
      cached_tokens = cached_match ? cached_match[1].to_i : 0

      reasoning_match = text.match(/"reasoning_tokens"\s*:\s*(\d+)/)
      reasoning_tokens = reasoning_match ? reasoning_match[1].to_i : 0

      model_match = text.match(/"model"\s*:\s*"([^"]+)"/)
      model = model_match ? model_match[1] : nil

      {
        "model" => model,
        "timestamp" => timestamp,
        "tokenUsage" => {
          "inputTokens" => input_tokens,
          "outputTokens" => output_tokens,
          "cacheReadTokens" => cached_tokens,
          "cacheWriteTokens" => 0,
          "reasoningTokens" => reasoning_tokens,
          "totalCents" => 0.0
        },
        "source" => "mitm"
      }
    end

    # =========================================================================
    # Usage Persistence
    # =========================================================================

    def persist_usage_statistic(terminal_session, events)
      totals = aggregate_events(events)
      models = events.filter_map { |e| e["model"] }.uniq
      source = events.any? { |e| e["source"] == "otlp_metrics" } ? "otlp_metrics" : "mitm"

      stat = terminal_session.usage_statistic || terminal_session.build_usage_statistic
      stat.assign_attributes(
        input_tokens: totals[:input_tokens],
        output_tokens: totals[:output_tokens],
        cache_write_tokens: totals[:cache_write_tokens],
        cache_read_tokens: totals[:cache_read_tokens],
        total_cents_precise: totals[:total_cents],
        cost_cents: totals[:total_cents].ceil,
        models: models,
        source: source,
        events_count: events.size,
        events_data: events
      )
      stat.save!

      Rails.logger.info(
        "[CodexAdapter] Session #{terminal_session.id} usage: " \
        "#{events.size} events, " \
        "in=#{totals[:input_tokens]} out=#{totals[:output_tokens]} " \
        "cache_r=#{totals[:cache_read_tokens]} " \
        "models=#{models.join(', ')}"
      )
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

    # =========================================================================
    # Config Generation
    # =========================================================================

    def generate_config_toml(workflow_config)
      workspace = workflow_config[:workspace] || "/workspace"
      model = workflow_config[:model]
      toml = +""
      toml << "model = \"#{model}\"\n\n" if model.present?
      toml << <<~TOML
        # Force file-based credential storage (no keyring in Docker)
        cli_auth_credentials_store = "file"

        # Auto-approve all commands without asking
        approval_policy = "never"

        # Full filesystem and network access
        sandbox_mode = "danger-full-access"

        [projects."#{workspace}"]
        trust_level = "trusted"

        [notice]
        hide_full_access_warning = true
        hide_rate_limit_model_nudge = true
      TOML
      if model.present?
        toml << "\n[notice.model_migrations]\n"
        toml << "\"#{model}\" = \"#{LATEST_TARGET_MODEL}\"\n"
      end

      otel_endpoint = Settings.otel.endpoint
      if otel_endpoint.present?
        toml << <<~TOML

          [otel]
          exporter = { otlp-http = { endpoint = "#{otel_endpoint}/v1/logs", protocol = "binary" } }
        TOML
      end

      toml
    end
  end
end
