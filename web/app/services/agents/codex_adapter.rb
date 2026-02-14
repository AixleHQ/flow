# frozen_string_literal: true

module Agents
  # OpenAI Codex CLI adapter for credential handling
  # Config: ~/.codex/auth.json + ~/.codex/config.toml
  # Auth: OAuth via OpenAI (Google login)
  class CodexAdapter < BaseAdapter
    METRIC_EVENT_NAME = "codex.sse_event"
    METRIC_EVENT_KIND_COMPLETED = "response.completed"
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

    # Session command: codex --yolo (interactive), codex -q (non-interactive)
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file
    def session_command(mode:, prompt: nil)
      if mode == "non_interactive" && prompt.present?
        "codex -q"
      else
        "codex --yolo"
      end
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
        lines << "url = \"#{s.url}\"" if s.url.present?
        if s.headers.present? && s.headers.any?
          header_pairs = s.headers.map { |k, v| "\"#{k}\" = \"#{v}\"" }.join(", ")
          lines << "http_headers = { #{header_pairs} }"
        end
        lines.join("\n")
      end
      { "#{home_dir}/.codex/config.toml" => "# MCP Servers (auto-generated)\n#{sections.join("\n\n")}\n" }
    end

    def mcp_merge_strategy
      :append_toml
    end

    # Default environment variables for Codex CLI runtime.
    def default_env_vars(session)
      route_token = session.route_token
      resource_attributes = "terminal_session_token=#{route_token}"

      {
        "OTEL_RESOURCE_ATTRIBUTES" => resource_attributes
      }.compact
    end

    # Parse OTLP payload and persist usage statistics for a terminal session.
    def ingest_usage(payload, terminal_session)
      totals = extract_usage_from_otlp_logs(payload, terminal_session.route_token)
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

    def generate_config_toml(workflow_config)
      workspace = workflow_config[:workspace] || "/workspace"
      <<~TOML
        # Auto-approve all commands without asking
        approval_policy = "never"

        # Full filesystem and network access
        sandbox_mode = "danger-full-access"

        [projects."#{workspace}"]
        trust_level = "trusted"

        [otel]
        environment = "prod"
        log_user_prompt = false
        exporter = { otlp-http = { endpoint = "http://otlp-ingest:4318/v1/logs", protocol = "json" } }
        metrics_exporter = { otlp-http = { endpoint = "http://otlp-ingest:4318/v1/metrics", protocol = "json" } }

        [notice]
        hide_full_access_warning = true
      TOML
    end

    def extract_usage_from_otlp_logs(payload, terminal_session_token)
      usage = { tokens: 0, cost_cents: 0 }
      return usage if terminal_session_token.blank?

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
            event_kind = attribute_string(attrs, "event.kind")
            next unless event_name == METRIC_EVENT_NAME && event_kind == METRIC_EVENT_KIND_COMPLETED

            total_tokens = attribute_number(attrs, "tool_token_count")
            if total_tokens.nil?
              input_tokens = attribute_number(attrs, "input_token_count")
              output_tokens = attribute_number(attrs, "output_token_count")
              total_tokens = input_tokens.to_i + output_tokens.to_i
            end

            usage[:tokens] += total_tokens.to_i if total_tokens
          end
        end
      end

      usage
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
  end
end
