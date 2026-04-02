# frozen_string_literal: true

module Agents
  # Google Gemini CLI adapter for credential handling
  #
  # Config structure (discovered from container):
  #   ~/.gemini/oauth_creds.json - OAuth tokens (access_token, refresh_token, etc.)
  #   ~/.gemini/gemini-credentials.json - Encrypted API key (when using API key auth)
  #   ~/.gemini/settings.json - Auth settings (selectedType: oauth-personal | gemini-api-key)
  #   ~/.gemini/google_accounts.json - Account info
  class GeminiCliAdapter < BaseAdapter
    METRIC_TOKENS_NAME = "gemini_cli.token.usage"
    METRIC_COST_NAME = "gemini_cli.cost.usage"
    LOG_EVENT_NAME = "gemini_cli.api_response"
    LEGACY_METRIC_NAMES = {
      "terminal.session.tokens" => METRIC_TOKENS_NAME,
      "terminal.session.cost" => METRIC_COST_NAME
    }.freeze

    API_KEY_CREDS_PATH = "gemini-credentials.json"

    def self.default_config_paths
      [ "~/.gemini/settings.json", "GEMINI.md" ]
    end

    def config_path
      "#{home_dir}/.gemini/#{API_KEY_CREDS_PATH}"
    end

    def home_dir
      "/home/gemini"
    end

    # Watcher monitors settings.json — created when user completes API key auth
    def auth_watch_path
      "#{home_dir}/.gemini/settings.json"
    end

    # Auth files to extract at cleanup
    def auth_file_paths
      [
        "#{home_dir}/.gemini/#{API_KEY_CREDS_PATH}",
        "#{home_dir}/.gemini/settings.json"
      ]
    end

    def auth_required_keys
      %w[security]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      config.dig("security", "auth", "selectedType").present?
    end

    # Not used directly — API key is extracted via decrypt in save_credentials
    def extract_credentials(config_content)
      {}
    end

    def generate_config(credentials, workflow_config = {})
      credentials
    end

    # API key auth: GEMINI_API_KEY env var + settings.json
    def config_files(credentials, workflow_config = {})
      {
        "#{home_dir}/.gemini/settings.json" => generate_settings(
          model: workflow_config[:model], auth_type: "gemini-api-key"
        ).to_json
      }
    end

    # Pass API key as env var — Gemini CLI picks it up automatically
    def default_env_vars(session)
      env = { "OTEL_RESOURCE_ATTRIBUTES" => "terminal_session_token=#{session.route_token}" }

      # Inject API key from credential
      credential = session.user&.agent_credentials&.find_by(agent_type: "gemini_cli")
      env["GEMINI_API_KEY"] = credential.config_data["api_key"] if credential&.config_data&.dig("api_key").present?

      env.compact
    end

    # Decrypt gemini-credentials.json from container.
    # Gemini CLI encrypts with AES-256-GCM, key derived via scrypt from hostname+username.
    def decrypt_credentials_file(encrypted_data, hostname, username = "root")
      parts = encrypted_data.strip.split(":")
      raise "Invalid format: expected iv:authTag:ciphertext" unless parts.length == 3

      iv = [ parts[0] ].pack("H*")
      auth_tag = [ parts[1] ].pack("H*")
      ciphertext = [ parts[2] ].pack("H*")

      salt = "#{hostname}-#{username}-gemini-cli"
      key = OpenSSL::KDF.scrypt("gemini-cli-oauth", salt: salt, N: 16384, r: 8, p: 1, length: 32)

      decipher = OpenSSL::Cipher.new("aes-256-gcm")
      decipher.decrypt
      decipher.key = key
      decipher.iv_len = iv.bytesize
      decipher.iv = iv
      decipher.auth_tag = auth_tag
      decrypted = decipher.update(ciphertext) + decipher.final

      # Structure: { "gemini-cli-api-key": { "default-api-key": "{\"token\":{\"accessToken\":\"...\"}}" } }
      data = JSON.parse(decrypted)
      api_key_json = data.dig("gemini-cli-api-key", "default-api-key")
      return nil unless api_key_json

      api_key_data = JSON.parse(api_key_json)
      api_key_data.dig("token", "accessToken")
    end

    # Session command: gemini --yolo (interactive), gemini -p (non-interactive)
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file
    def session_command(mode:, prompt: nil, model: nil)
      model ? "gemini --model #{Shellwords.shellescape(model)} --yolo" : "gemini --yolo"
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
        if s.transport.to_s == "stdio"
          entry["command"] = s.command if s.respond_to?(:command)
          entry["args"] = s.args if s.respond_to?(:args) && s.args.present?
          entry["env"] = s.env if s.respond_to?(:env) && s.env.present?
        else
          entry["httpUrl"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        mcp_servers[s.name] = entry
      end
      { "#{home_dir}/.gemini/settings.json" => { "mcpServers" => mcp_servers }.to_json }
    end

    def mcp_merge_strategy
      :merge_json
    end

    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # =================================================================
    # Environment Variables (from session/credential metadata)
    # =================================================================

    # Fetch available models from Google Generative Language API.
    GEMINI_MODELS_URL = "https://generativelanguage.googleapis.com/v1beta/models"

    def fetch_available_models(credentials)
      api_key = credentials["api_key"]
      access_token = credentials["access_token"]

      uri = URI(GEMINI_MODELS_URL)
      req = Net::HTTP::Get.new(uri)

      if api_key.present?
        uri.query = URI.encode_www_form(key: api_key, pageSize: 100)
        req = Net::HTTP::Get.new(uri)
      elsif access_token.present?
        uri.query = URI.encode_www_form(pageSize: 100)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{access_token}"
      else
        return []
      end

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      (data["models"] || []).filter_map do |m|
        methods = m["supportedGenerationMethods"] || []
        next unless methods.include?("generateContent")

        model_id = m["name"].to_s.sub("models/", "")
        display_name = m["displayName"] || model_id

        # Only keep models that support caching (reliable indicator of full text/agent capability)
        next unless methods.include?("createCachedContent")

        { model_id: model_id, display_name: display_name, description: m["description"].to_s.truncate(120) }
      end
    rescue StandardError => e
      Rails.logger.warn("[GeminiCliAdapter] fetch_available_models failed: #{e.message}")
      []
    end


    # Parse OTLP payload and persist usage statistics for a terminal session.
    def ingest_usage(payload, terminal_session)
      Rails.logger.info("[GeminiCliAdapter] Session #{terminal_session.id}: OTLP payload=#{payload.to_json}")

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

    def generate_settings(model: nil, auth_type: "gemini-api-key")
      settings = {
        "security" => {
          "auth" => { "selectedType" => auth_type },
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
          "otlpEndpoint" => Settings.otel.metrics_endpoint.to_s.sub(%r{/v1/\w+\z}, ""),
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
      settings["model"] = { "name" => model } if model.present?
      settings
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
          per_model = Hash.new do |hash, key|
            hash[key] = {
              model: nil,
              token_breakdown: Hash.new(0),
              cost_usd: 0.0,
              timestamp_ns: nil
            }
          end

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
              point_model = extract_model(dp_attrs)
              model_key = point_model.presence || "__unknown__"
              entry = per_model[model_key]
              entry[:model] ||= point_model
              entry[:timestamp_ns] ||= data_point["timeUnixNano"]

              case name
              when METRIC_TOKENS_NAME
                token_type = normalize_token_type(attribute_string(dp_attrs, "type") || attribute_string(dp_attrs, "token_type"))
                entry[:token_breakdown][token_type] += value.to_i
              when METRIC_COST_NAME
                entry[:cost_usd] += value.to_f
              end
            end
          end

          per_model.each_value do |entry|
            token_breakdown = entry[:token_breakdown]
            cost_usd = entry[:cost_usd]
            next if token_breakdown.values.sum.zero? && cost_usd.zero?

            events << build_usage_event(
              model: entry[:model],
              timestamp_ns: entry[:timestamp_ns],
              input_tokens: token_breakdown["input"],
              output_tokens: token_breakdown["output"],
              cache_read_tokens: token_breakdown["cacheRead"],
              cache_write_tokens: token_breakdown["cacheCreation"],
              total_cents: (cost_usd * 100).round(6)
            )
          end
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
      when "thought", "tool" then "output"
      when "cache" then "cacheRead"
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
