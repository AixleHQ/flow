# frozen_string_literal: true

require "base64"

module Agents
  # OpenAI Codex CLI adapter for credential handling
  # Config: ~/.codex/auth.json + ~/.codex/config.toml
  # Auth: OAuth via OpenAI (Google login)
  class CodexAdapter < BaseAdapter
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

    # Session command: codex --yolo (interactive), codex exec (non-interactive)
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file
    def session_command(mode:, prompt: nil)
      "codex --yolo"
    end

    # Context file: /workspace/AGENTS.md (auto-read by Codex from workspace root)
    def context_file_path
      "/workspace/AGENTS.md"
    end

    # Skill files: ~/.codex/skills/<name>/SKILL.md with YAML front matter (user-scoped)
    def skill_files(skills)
      files = {}
      skills.each do |skill|
        next if skill.content.blank?

        description = (skill.description || skill.title || skill.name).to_s
        front_matter = "---\nname: #{skill.name}\ndescription: #{description.to_json}\n---\n\n"
        files["#{home_dir}/.codex/skills/#{skill.name}/SKILL.md"] = front_matter + skill.content
      end
      files
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

    # Default environment variables for Codex CLI runtime.
    # MITM_TRACKED_DOMAINS limits logging to chatgpt.com (Codex API host).
    def default_env_vars(_session)
      {
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => "chatgpt.com"
      }
    end

    # Log files to collect from container after session ends.
    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # Collect usage from MITM log at session cleanup.
    #
    # Flow:
    #   1. Parse MITM log for chatgpt.com/backend-api/codex/responses responses
    #   2. Extract `response.completed` SSE events from each response body tail
    #   3. Build normalized events with token breakdown from OpenAI `usage` object
    #   4. Persist as UsageStatistic
    def collect_usage(terminal_session, artifacts = {})
      mitm_log = artifacts["logs/http.log"]

      log_lines = (mitm_log || "").lines.size
      Rails.logger.info("[CodexAdapter] Session #{terminal_session.id}: MITM log #{mitm_log.present? ? "#{mitm_log.bytesize}B, #{log_lines} lines" : 'EMPTY'}")

      if mitm_log.present?
        mitm_log.each_line.first(20).each_with_index do |line, i|
          entry = JSON.parse(line.strip) rescue nil
          next unless entry

          Rails.logger.info("[CodexAdapter] line #{i}: dir=#{entry['direction']} host=#{entry['host']} path=#{entry['path']} status=#{entry['status_code']} body_enc=#{entry['body_encoding']} body_len=#{entry['body']&.length}")
        end
      end

      events = extract_events_from_mitm(mitm_log)

      if events.empty?
        Rails.logger.warn("[CodexAdapter] No usage events in MITM log for session #{terminal_session.id}")
        return
      end

      persist_usage_statistic(terminal_session, events)
    end

    private

    CODEX_RESPONSES_PATH = "/backend-api/codex/responses"

    # =========================================================================
    # MITM Log Parsing → Normalized Events
    # =========================================================================

    # Parse MITM log and extract usage from /codex/responses response bodies.
    #
    # Codex uses OpenAI Responses API with chunked NDJSON (not SSE).
    # The final chunk is a large response.completed JSON with `usage` at the end.
    # Our tail buffer may only capture the end — so we regex-extract usage directly.
    def extract_events_from_mitm(log_content)
      events = []

      (log_content || "").each_line do |line|
        entry = JSON.parse(line.strip)
        next unless entry["direction"] == "response"
        next unless entry["path"]&.start_with?(CODEX_RESPONSES_PATH)
        next unless entry["status_code"] == 200

        text = decode_body(entry)
        next if text.blank?

        Rails.logger.info("[CodexAdapter] Response body (#{text.bytesize}B): first 500 chars: #{text[0..499].inspect}")
        Rails.logger.info("[CodexAdapter] Response body last 500 chars: #{text[-500..].inspect}")

        event = extract_usage_from_response_body(text, entry["ts"])
        Rails.logger.info("[CodexAdapter] Usage extracted: #{event ? 'YES' : 'NO'}")
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

      stat = terminal_session.usage_statistic || terminal_session.build_usage_statistic
      stat.assign_attributes(
        input_tokens: totals[:input_tokens],
        output_tokens: totals[:output_tokens],
        cache_write_tokens: totals[:cache_write_tokens],
        cache_read_tokens: totals[:cache_read_tokens],
        total_cents_precise: totals[:total_cents],
        cost_cents: totals[:total_cents].ceil,
        models: models,
        source: "mitm",
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
      <<~TOML
        # Auto-approve all commands without asking
        approval_policy = "never"

        # Full filesystem and network access
        sandbox_mode = "danger-full-access"

        [projects."#{workspace}"]
        trust_level = "trusted"

        [notice]
        hide_full_access_warning = true

        [notice.model_migrations]
        "gpt-5.2-codex" = "gpt-5.3-codex"
      TOML
    end
  end
end
