# frozen_string_literal: true

require "base64"

module Agents
  # OpenAI Codex CLI adapter for credential handling
  # Config: ~/.codex/auth.json + ~/.codex/config.toml
  # Auth: OAuth via OpenAI (Google login)
  class CodexAdapter < BaseAdapter
    # Startup model-migration dialog suppression.
    #
    # Codex CLI shows the "try the new model" dialog when the model it is about to
    # run carries an `upgrade` entry in the server model catalog and
    # `notice.model_migrations[<current model>]` does not already point at that
    # exact upgrade target (codex-rs/tui/src/app/startup_prompts.rs ->
    # should_show_model_migration_prompt). The current model is the session model
    # when one is configured and the catalog default otherwise, so the
    # acknowledgement map has to cover every migratable model in the catalog, not
    # only the configured one.
    #
    # The map is therefore built from the live catalog (see fetch_model_upgrades),
    # which is the same source the CLI reads — a hardcoded target slug goes stale
    # the moment OpenAI moves the migration target and the dialog comes back.
    # FALLBACK_MODEL_MIGRATIONS is the last resort for when the catalog is
    # unreachable (expired token, network failure); it mirrors the mappings the CLI
    # ships in codex-rs/models-manager/models.json.
    FALLBACK_MODEL_MIGRATIONS = {
      "gpt-5.4" => "gpt-5.6-terra",
      "gpt-5.4-mini" => "gpt-5.6-luna"
    }.freeze

    # Migration mappings become TOML keys, and the CLI compares the *parsed* key
    # against the model slug — so entries are restricted to slug-shaped strings that
    # need no escaping at all, rather than leaning on escape handling inside a
    # quoted key (see toml_string) for something the suppression depends on.
    MODEL_SLUG_FORMAT = /\A[A-Za-z0-9._-]+\z/

    # The working directory every agent container runs the CLI in. Codex asks
    # "Do you trust the contents of this directory?" for any cwd that is not a
    # trusted project, and in a non_interactive session nobody can answer it — the
    # step just sits at `ready` forever. Both places that grant trust (config.toml
    # and the launch command) key off this one constant.
    DEFAULT_WORKSPACE = "/workspace"

    # Codex splits a `-c` override on ".", so a workspace path containing a dot
    # cannot be addressed this way, and the launch command travels through
    # `tmux send-keys -t agent '<cmd>'` (AgentBaseStrategy#send_tmux_sequence), so
    # anything needing shell quoting cannot go on the command line either. Paths
    # that fail this fall back to the config.toml entry alone.
    CLI_TRUSTABLE_WORKSPACE_FORMAT = %r{\A/[A-Za-z0-9_/-]+\z}

    def self.default_config_paths
      [ "~/.codex/config.toml", "AGENTS.md" ]
    end

    def config_path
      "#{home_dir}/.codex/auth.json"
    end

    def home_dir
      "/home/codex"
    end

    # Where `skills add -g -a codex` puts a skill: $CODEX_HOME/skills, defaulting to
    # ~/.codex/skills. Hand-written skills are written here directly, alongside the
    # registry skills the CLI installs for this agent.
    def skills_install_path
      "#{home_dir}/.codex/skills"
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

    # Codex OAuth access/id tokens are JWTs carrying an `exp` claim. Surface the
    # soonest expiry (epoch ms) so AgentCredential#expires_at is populated and the
    # proactive-refresh sweep selects the credential before it expires (instead of
    # only refreshing reactively on a 401).
    def token_expires_at(credentials)
      tokens = credentials["tokens"]
      return nil unless tokens.is_a?(Hash)

      jwt_exp_ms(tokens["access_token"]) || jwt_exp_ms(tokens["id_token"])
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
        "#{home_dir}/.codex/config.toml" => generate_config_toml(workflow_config, credentials)
      }
    end

    # Config files needed before auth starts (config.toml with file-based credential store)
    def auth_setup_files
      { "#{home_dir}/.codex/config.toml" => generate_config_toml({}) }
    end

    # Session command: always codex --yolo, with workspace trust granted inline.
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file.
    def session_command(mode:, prompt: nil, model: nil, workspace: DEFAULT_WORKSPACE)
      model_flag = model ? " --model #{Shellwords.shellescape(model)}" : ""
      "codex#{model_flag} --yolo#{cli_trust_flag(workspace)}"
    end

    # Grant workspace trust on the command line as well as in config.toml.
    #
    # `--yolo` does NOT cover the trust dialog — it is the one startup prompt that
    # is keyed on the cwd rather than on a notice flag, and a non_interactive
    # session that reaches it never produces another byte (task #605: run 3190,
    # step run 3476, session 3834 sat at `ready` for ~52 minutes on 0 tokens).
    # config.toml alone is not a safe place to keep the only copy: it is written
    # once by the credential step and then read-modify-written by the MCP append, so
    # any container hiccup on that path leaves a file that parses fine and trusts
    # nothing. A `-c` override is applied from argv, so it cannot be lost that way.
    def cli_trust_flag(workspace = DEFAULT_WORKSPACE)
      return "" unless workspace.to_s.match?(CLI_TRUSTABLE_WORKSPACE_FORMAT)

      " -c projects.#{workspace}.trust_level=trusted"
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
        lines << "[mcp_servers.#{toml_string(s.name)}]"
        if s.transport.to_s == "stdio"
          lines << "command = #{toml_string(s.command)}" if s.respond_to?(:command)
          if s.respond_to?(:args) && s.args.present?
            args_toml = mcp_stdio_args(s).map { |a| toml_string(a) }.join(", ")
            lines << "args = [#{args_toml}]"
          end
          env = mcp_stdio_env(s)
          if env.present?
            env_pairs = env.map { |k, v| "#{toml_string(k)} = #{toml_string(v)}" }.join(", ")
            lines << "env = { #{env_pairs} }"
          end
        else
          lines << "url = #{toml_string(s.url)}" if s.url.present?
          if s.headers.present? && s.headers.any?
            header_pairs = s.headers.map { |k, v| "#{toml_string(k)} = #{toml_string(v)}" }.join(", ")
            lines << "http_headers = { #{header_pairs} }"
          end
        end
        lines.join("\n")
      end
      { "#{home_dir}/.codex/config.toml" => "# MCP Servers (auto-generated)\n#{sections.join("\n\n")}\n" }
    end

    # Render a value as a TOML basic string with the double-quote delimiters and
    # the required escapes (§7 quick win). Without this, a header/token/arg value
    # containing a quote or backslash corrupts config.toml (or allows injection).
    # @param value [#to_s]
    # @return [String] a quoted, escaped TOML basic string
    def toml_string(value)
      escaped = value.to_s.gsub(/[\\"\u0000-\u001F]/) do |ch|
        case ch
        when "\\" then "\\\\"
        when '"' then '\\"'
        when "\b" then '\\b'
        when "\t" then '\\t'
        when "\n" then '\\n'
        when "\f" then '\\f'
        when "\r" then '\\r'
        else format('\\u%04x', ch.ord)
        end
      end
      "\"#{escaped}\""
    end

    def mcp_merge_strategy
      :append_toml
    end

    MODEL_DESCRIPTION_LIMIT = 120

    # Fetch the models to offer in the picker from the Codex catalog.
    # When an AgentCredential record is passed via `credential:`, expired
    # access tokens are automatically refreshed using the stored refresh_token.
    #
    # Endpoints, headers, the client-version gate and JSON parsing live in
    # Codex::Api; what stays here is the decision of which models to offer and
    # when a rejected token is worth refreshing.
    def fetch_available_models(credentials, credential: nil)
      access_token = credentials.dig("tokens", "access_token")
      return [] if access_token.blank?

      catalog(access_token, credential: credential)
        .select(&:listed?)
        .map do |model|
          {
            model_id: model.slug,
            display_name: model.display_name,
            description: model.description.truncate(MODEL_DESCRIPTION_LIMIT)
          }
        end
    rescue StandardError => e
      Rails.logger.warn("[CodexAdapter] fetch_available_models failed: #{e.message}")
      []
    end

    # ChatGPT-backed Codex logins expose percentage-based primary and secondary
    # quota windows. API-key logins are pay-as-you-go and have no subscription
    # windows to report.
    def fetch_subscription_usage(credentials)
      access_token = credentials.dig("tokens", "access_token")
      return nil if access_token.blank?

      # Current Codex auth.json stores account_id beside the OAuth tokens. Keep
      # accepting the former top-level shape for credentials captured by older
      # CLI releases.
      account_id = credentials.dig("tokens", "account_id").presence || credentials["account_id"]
      body = Codex::Api.usage(access_token:, account_id:)
      rate_limit = body["rate_limit"] || {}
      windows = %w[primary_window secondary_window].filter_map do |key|
        window = rate_limit[key]
        next unless window.is_a?(Hash) && window["used_percent"].present?

        {
          key: "codex_#{key.delete_suffix('_window')}",
          utilization: window["used_percent"].to_f,
          resets_at: window["reset_at"] && Time.at(window["reset_at"].to_i).utc.iso8601,
          window_duration_mins: window["limit_window_seconds"]&.to_f&./(60.0)
        }.compact
      end

      individual = body.dig("spend_control", "individual_limit")
      extra_usage = if individual.is_a?(Hash)
        {
          enabled: true,
          utilization: individual["used_percent"]&.to_f,
          monthly_limit: numeric_value(individual["limit"]),
          used_credits: numeric_value(individual["used"])
        }
      end

      { status: "ok", windows:, extra_usage: }
    rescue Codex::Api::UnauthorizedError
      { status: "unauthorized" }
    rescue Codex::Api::HTTPError => e
      e.status == 429 ? { status: "rate_limited" } : { status: "unavailable" }
    rescue Codex::Api::ApiError => e
      Rails.logger.warn("[CodexAdapter] subscription usage fetch failed: #{e.class}: #{e.message}")
      { status: "unavailable" }
    end

    # Refresh an expired access token using the stored refresh_token.
    # Persists new tokens back to the AgentCredential record.
    # Returns the new access_token on success, nil on failure.
    def refresh_access_token!(credential)
      refresh_token = credential.config_data.dig("tokens", "refresh_token")
      return nil if refresh_token.blank?

      tokens = Codex::Api.refresh_tokens(refresh_token: refresh_token)

      current_tokens = credential.config_data["tokens"] || {}
      # Never discard the prior refresh_token/id_token when the server omits a
      # rotated one (RFC: keep the old until a new pair is committed).
      new_tokens = current_tokens.merge(
        "access_token" => tokens.access_token,
        "refresh_token" => tokens.refresh_token || current_tokens["refresh_token"],
        "id_token" => tokens.id_token || current_tokens["id_token"]
      ).compact

      new_config = credential.config_data.merge("tokens" => new_tokens, "last_refresh" => Time.current.iso8601)
      # Persist under a row lock with the rotation guard so a concurrent session
      # cleanup or sweep can't clobber a newer token.
      persisted = persist_refreshed!(credential, new_config)
      Rails.logger.info("[CodexAdapter] Access token refreshed for credential #{credential.id}")

      persisted.dig("tokens", "access_token")
    rescue StandardError => e
      Rails.logger.warn("[CodexAdapter] Token refresh error: #{e.class}: #{e.message}")
      nil
    end

    def numeric_value(value)
      return nil if value.nil?

      number = value.to_f
      number % 1 == 0 ? number.to_i : number
    end
    private :numeric_value

    # =========================================================================
    # Launch-time Credential Preflight (see BaseAdapter#credential_preflight)
    # =========================================================================

    # Read back auth.json from the container. The gate is existence + non-zero
    # size only (task #1327, owner decision in board comment 8140) — content is
    # still parsed and validated against Codex's own auth semantics (a `tokens`
    # object with a present access_token or refresh_token — see #auth_complete?)
    # purely to populate the diagnostic (json_parse_status, tokens_object_present,
    # access_token_present, refresh_token_present), not to decide validity.
    # credential_write_result reports are likewise diagnostic-only: a credential
    # write failure this launch does not mean the file already on disk is invalid
    # (task #1327 — Session 5744 used unchanged token bytes that later succeeded),
    # so write result is logged as evidence only, never a gate.
    #
    # Exactly one read-back. No retry, no rewrite, no delay, no token refresh.
    def credential_preflight(runtime, container, container_id, credential_write_result: nil)
      script = <<~JAVASCRIPT
        const fs = require("fs");
        const crypto = require("crypto");
        const path = #{config_path.to_json};
        const diagnostic = {
          exists: false, size: null, owner_uid: null, owner_gid: null, mode: null,
          sha256: null, json_parse_status: "not_attempted", tokens_object_present: false,
          access_token_present: false, refresh_token_present: false,
          effective_uid: process.geteuid(), home: process.env.HOME || null,
          codex_home: process.env.CODEX_HOME || null
        };
        try {
          const stat = fs.statSync(path);
          const content = fs.readFileSync(path);
          diagnostic.exists = true;
          diagnostic.size = stat.size;
          diagnostic.owner_uid = stat.uid;
          diagnostic.owner_gid = stat.gid;
          diagnostic.mode = (stat.mode & 0o7777).toString(8).padStart(4, "0");
          diagnostic.sha256 = crypto.createHash("sha256").update(content).digest("hex");
          try {
            const auth = JSON.parse(content.toString("utf8"));
            diagnostic.json_parse_status = "valid";
            diagnostic.tokens_object_present = !!auth.tokens && typeof auth.tokens === "object" && !Array.isArray(auth.tokens);
            diagnostic.access_token_present = diagnostic.tokens_object_present && typeof auth.tokens.access_token === "string" && auth.tokens.access_token.trim().length > 0;
            diagnostic.refresh_token_present = diagnostic.tokens_object_present && typeof auth.tokens.refresh_token === "string" && auth.tokens.refresh_token.trim().length > 0;
          } catch (_) {
            diagnostic.json_parse_status = "invalid";
          }
        } catch (error) {
          diagnostic.read_error = error.code || error.name;
        }
        process.stdout.write(JSON.stringify(diagnostic));
      JAVASCRIPT

      stdout, stderr, status = runtime.exec(container, [ "node", "-e", script ])
      diagnostic = JSON.parse(Array(stdout).join)
      diagnostic.merge!(
        "event" => "codex_auth_preflight",
        "credential_write_result" => credential_write_result_label(credential_write_result),
        "runtime" => runtime.class.name,
        "container_id" => container_id
      )

      code = preflight_error_code(diagnostic, status)
      { diagnostic: diagnostic, valid: code.nil?, error_code: code }
    rescue JSON::ParserError
      diagnostic = {
        "event" => "codex_auth_preflight",
        "credential_write_result" => credential_write_result_label(credential_write_result),
        "runtime" => runtime.class.name,
        "container_id" => container_id,
        "probe_status" => status,
        "probe_error" => Array(stderr).join.truncate(200)
      }
      { diagnostic: diagnostic, valid: false, error_code: "probe_failed" }
    end

    # task #1327 (owner decision, board comment 8140): the gate is existence +
    # non-zero size only. JSON parse status and tokens/access_token/refresh_token
    # presence are NOT gates — a non-empty-but-malformed or token-less file passes
    # preflight (that is a deliberate, accepted risk; see the same comment). They
    # are still computed and logged as diagnostic evidence for #1308, just never
    # checked here. credential_write_result is likewise evidence only, never a
    # gate: the file on disk is the ground truth.
    def preflight_error_code(diagnostic, probe_status)
      return "probe_failed" unless probe_status.to_i.zero?
      return "auth_file_missing" unless diagnostic["exists"]
      "auth_file_empty" unless diagnostic["size"].to_i > 0
    end
    private :preflight_error_code

    def credential_write_result_label(write_result)
      case write_result
      when true then "success"
      when false then "failed"
      else "not_attempted"
      end
    end
    private :credential_write_result_label

    # Proactive-refresh hook (Temporal sweep). Thin wrapper over the reactive
    # refresh_access_token! which persists under a row lock via persist_refreshed!.
    # @param credential [AgentCredential]
    # @return [Hash] { status: :refreshed | :error, detail: String | nil }
    def refresh!(credential)
      new_token = refresh_access_token!(credential)
      new_token ? { status: :refreshed, detail: nil }
                : { status: :error, detail: "codex token refresh failed" }
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

      UsageStatistics::Accumulator.record(terminal_session: terminal_session, events: new_events)
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

    # Old -> new model slug pairs for `[notice.model_migrations]`, ordered so the
    # generated config.toml is stable across runs. Catalog entries win over the
    # static fallback; anything that is not slug-shaped is dropped rather than
    # written into the TOML.
    #
    # The catalog is read live on every config write rather than cached: the
    # migration target is the one value that must not go stale, and config.toml is
    # generated once per container start — the same endpoint already answers a
    # request per model-picker load.
    def model_migrations(credentials)
      FALLBACK_MODEL_MIGRATIONS
        .merge(fetch_model_upgrades(credentials))
        .select { |from, to| from.to_s.match?(MODEL_SLUG_FORMAT) && to.to_s.match?(MODEL_SLUG_FORMAT) }
        .sort
        .to_h
    end

    # slug => upgrade target for every catalog model that has one, including models
    # hidden from the picker (`visibility != "list"`): a session pinned to an older
    # model is exactly the case that gets the dialog.
    def fetch_model_upgrades(credentials)
      access_token = credentials&.dig("tokens", "access_token")
      return {} if access_token.blank?

      Codex::Api.models(access_token: access_token)
                .select(&:upgradable?)
                .to_h { |model| [ model.slug, model.upgrade_target ] }
    rescue StandardError => e
      Rails.logger.warn("[CodexAdapter] fetch_model_upgrades failed: #{e.message}")
      {}
    end

    # A rejected access token is the one failure worth retrying: `credential`
    # carries the refresh token, so refresh once and ask again. Everything else
    # propagates to the caller's rescue.
    def catalog(access_token, credential: nil)
      Codex::Api.models(access_token: access_token)
    rescue Codex::Api::UnauthorizedError
      raise unless credential

      new_token = refresh_access_token!(credential)
      raise unless new_token

      Codex::Api.models(access_token: new_token)
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

    def generate_config_toml(workflow_config, credentials = {})
      workspace = workflow_config[:workspace] || DEFAULT_WORKSPACE
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

        # Every startup prompt Codex CLI can block the session on, pre-acknowledged.
        # The two hide_*_migration_prompt keys cover the model dialogs the CLI still
        # gates on a dedicated flag; the catalog-driven map below covers the rest.
        [notice]
        hide_full_access_warning = true
        hide_rate_limit_model_nudge = true
        hide_gpt5_1_migration_prompt = true
        "hide_gpt-5.1-codex-max_migration_prompt" = true
      TOML

      migrations = model_migrations(credentials)
      if migrations.any?
        toml << "\n[notice.model_migrations]\n"
        migrations.each { |from, to| toml << "\"#{from}\" = \"#{to}\"\n" }
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
