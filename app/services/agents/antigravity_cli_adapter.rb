# frozen_string_literal: true

require "shellwords"

module Agents
  # Google Antigravity CLI adapter.
  #
  # Auth model (confirmed against the real 1.1.27 `agy` binary, and against a
  # completed live Google OAuth login on a container host — see PR #179 review):
  # run with no flags and no GEMINI_API_KEY, its interactive welcome prompt only
  # offers "Google OAuth" or "Use a Google Cloud project" — both end up going
  # through the same Google OAuth authorization-code flow (just different
  # scopes), and neither offers a raw-API-key option. That flow uses a
  # Google-hosted redirect (`https://antigravity.google/oauth-callback`), not a
  # localhost callback, so it never needs the container to receive anything: the
  # user opens the printed URL in their own browser and either gets redirected
  # straight through, or pastes the resulting authorization code back into the
  # terminal by hand. And in a container specifically — confirmed via the CLI's
  # own log output ("composite_token_storage.go: Using file-based token storage
  # because no D-Bus session bus detected") — `agy` automatically persists the
  # login to a file instead of the host OS keyring, exactly like every other
  # adapter's CLI-driven login here. So, per review feedback, this adapter
  # drives the real `agy` login directly (default #auth_launch_commands_for,
  # same as Gemini/Codex/Claude) instead of a bespoke script, and captures
  # whatever `agy` writes under its own config directory.
  #
  # A completed real login confirmed the token lands at
  # `~/.gemini/antigravity-cli/antigravity-oauth-token` (no file extension), as
  # `{"token":{"access_token":...,"token_type":"Bearer","refresh_token":...,
  # "expiry":"<ISO8601>"},"auth_method":"consumer"}` — nested under `token`,
  # unlike GeminiCliAdapter's flat `oauth_creds.json`. `auth_method` reflects
  # which welcome-prompt option was used ("consumer" for "Google OAuth"); it is
  # kept alongside the token so a future Cloud-project-specific need (e.g. a
  # required GOOGLE_CLOUD_PROJECT env var) has it on hand.
  class AntigravityCliAdapter < BaseAdapter
    SETTINGS_PATH = ".gemini/antigravity-cli/settings.json"
    OAUTH_TOKEN_PATH = ".gemini/antigravity-cli/antigravity-oauth-token"

    # API-equivalent prices in USD per million tokens. Antigravity's result event
    # reports cache reads as a subset of input tokens, so cached input is removed
    # from the regular input bucket before pricing. Keep this table beside the
    # runtime's model catalogue: model ids are Antigravity ids, not provider ids.
    MODEL_PRICING = {
      "gemini-3.8-flash-high" => { input: 0.75, output: 3.75, cache_read: 0.075 },
      "gemini-3.8-flash-medium" => { input: 0.75, output: 3.75, cache_read: 0.075 },
      "gemini-3.8-flash-low" => { input: 0.75, output: 3.75, cache_read: 0.075 },
      "gemini-3.7-flash-high" => { input: 0.75, output: 3.75, cache_read: 0.075 },
      "gemini-3.7-flash-medium" => { input: 0.75, output: 3.75, cache_read: 0.075 },
      "gemini-3.7-flash-low" => { input: 0.75, output: 3.75, cache_read: 0.075 },
      "gemini-3.6-flash-high" => { input: 1.50, output: 9.00, cache_read: 0.15 },
      "gemini-3.6-flash-medium" => { input: 1.50, output: 9.00, cache_read: 0.15 },
      "gemini-3.6-flash-low" => { input: 1.50, output: 9.00, cache_read: 0.15 },
      "gemini-pro-agent" => { input: 2.50, output: 15.00, cache_read: 0.25 },
      "gemini-3.1-pro-low" => { input: 2.50, output: 15.00, cache_read: 0.25 },
      "claude-sonnet-4-6" => { input: 3.00, output: 15.00, cache_read: 0.30 },
      "claude-opus-4-6-thinking" => { input: 5.00, output: 25.00, cache_read: 0.50 },
      "gpt-oss-120b-medium" => { input: 0.15, output: 0.60, cache_read: 0.015 }
    }.freeze

    # Used only when the live catalogue is unavailable or no access token was
    # captured. The API response is the source of truth for signed-in users.
    FALLBACK_MODELS = [
      { model_id: "gemini-3.8-flash-high", display_name: "Gemini 3.8 Flash (High)" },
      { model_id: "gemini-3.8-flash-medium", display_name: "Gemini 3.8 Flash (Medium)" },
      { model_id: "gemini-3.8-flash-low", display_name: "Gemini 3.8 Flash (Low)" },
      { model_id: "gemini-3.7-flash-high", display_name: "Gemini 3.7 Flash (High)" },
      { model_id: "gemini-3.7-flash-medium", display_name: "Gemini 3.7 Flash (Medium)" },
      { model_id: "gemini-3.7-flash-low", display_name: "Gemini 3.7 Flash (Low)" },
      { model_id: "gemini-3.6-flash-high", display_name: "Gemini 3.6 Flash (High)" },
      { model_id: "gemini-3.6-flash-medium", display_name: "Gemini 3.6 Flash (Medium)" },
      { model_id: "gemini-3.6-flash-low", display_name: "Gemini 3.6 Flash (Low)" },
      { model_id: "gemini-pro-agent", display_name: "Gemini Pro" },
      { model_id: "gemini-3.1-pro-low", display_name: "Gemini 3.1 Pro (Low)" },
      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6 (Thinking)" },
      { model_id: "claude-opus-4-6-thinking", display_name: "Claude Opus 4.6 (Thinking)" },
      { model_id: "gpt-oss-120b-medium", display_name: "GPT-OSS 120B (Medium)" }
    ].freeze

    def self.default_config_paths
      [ "~/.gemini/antigravity-cli/settings.json", "~/.gemini/config/mcp_config.json", "GEMINI.md" ]
    end

    def home_dir = "/home/antigravity"
    def config_path = "#{home_dir}/#{OAUTH_TOKEN_PATH}"

    # Google installed-app OAuth: a 1h access token and a refresh token Google does not
    # rotate (measured on a production credential 2026-09-24: `expires_in` 3599, no
    # `refresh_token` in the response). Renewable server-side only when the platform
    # holds agy's OAuth client — see Settings.agents.antigravity.
    def credential_lifecycle
      return { expiry: :none, refresh: :container_only, rotation: :static, nominal_ttl: 1.hour }.freeze unless oauth_client

      { expiry: :token, refresh: :server, rotation: :static, nominal_ttl: 1.hour }.freeze
    end

    GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
    # agy embeds a second client for the "Use a Google Cloud project" login. Which login
    # uses it is unverified, so those credentials publish no expiry and stay with the CLI.
    SERVER_REFRESHABLE_AUTH_METHODS = %w[consumer].freeze

    def token_expires_at(credentials)
      return nil unless server_refreshable?(credentials)

      expiry_ms(credentials["expiry"])
    end

    # margin_ms is ignored: a call is already the decision to refresh, and with a refresh
    # token that does not rotate an early refresh costs nothing.
    def refresh!(credential, margin_ms: nil) # rubocop:disable Lint/UnusedMethodArgument
      credentials = credential.config_data
      return { status: :not_needed, detail: nil, permanent: false } unless server_refreshable?(credentials)

      refresh_token = credentials["refresh_token"]
      return { status: :error, detail: "no refresh token stored — sign in again", permanent: true } if refresh_token.blank?

      response = Net::HTTP.post_form(URI(GOOGLE_TOKEN_URL), {
        grant_type: "refresh_token", refresh_token: refresh_token,
        client_id: oauth_client[:id], client_secret: oauth_client[:secret]
      })
      body = parse_json(response.body)
      unless response.is_a?(Net::HTTPSuccess) && body["access_token"].present?
        return { status: :error, detail: "#{response.code}: #{response.body.to_s.truncate(200)}",
                 permanent: body["error"] == "invalid_grant" }
      end

      persist_refreshed!(credential, credentials.merge(
        "access_token" => body["access_token"],
        "token_type" => body["token_type"] || credentials["token_type"],
        "refresh_token" => body["refresh_token"].presence || refresh_token,
        "expiry" => body["expires_in"].to_i.seconds.from_now.utc.iso8601(9)
      ))
      { status: :refreshed, detail: nil }
    end

    # Watch the OAuth token file, not settings.json: settings.json is written
    # up front by #auth_setup_files, before the user has logged in at all, so
    # watching it would report success prematurely.
    def auth_watch_path = config_path

    def auth_file_paths = [ config_path, "#{home_dir}/#{SETTINGS_PATH}" ]
    def auth_required_keys = %w[token.access_token]

    def auth_complete?(content)
      parse_json(content).dig("token", "access_token").present?
    end

    def extract_credentials(content)
      parsed = parse_json(content)
      token = parsed["token"]
      return {} unless token.is_a?(Hash)

      token.slice("access_token", "refresh_token", "token_type", "expiry")
           .merge("auth_method" => parsed["auth_method"])
           .compact
    end

    # Rebuilds the exact shape `agy` itself writes, so a container seeded from a
    # stored credential looks identical to one that just logged in live.
    def generate_config(credentials, _workflow_config = {})
      {
        "token" => credentials.except("auth_method"),
        "auth_method" => credentials["auth_method"]
      }.compact
    end

    def config_files(credentials, _workflow_config = {})
      {
        "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json,
        config_path => generate_config(credentials).to_json
      }
    end

    # Written before auth starts so the auth terminal already has telemetry/tips
    # disabled when `agy` itself launches (see AgentAuthStrategy#before_exec).
    def auth_setup_files
      { "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json }
    end

    # `agy` is a Go binary, so it honours HTTP(S)_PROXY and its traffic already goes
    # through the container's MITM proxy — but until now nothing collected the log, so 51
    # production sessions in 30 days produced zero HTTP records and the refresh protocol
    # stayed a guess read out of the binary. Google's token endpoint is the one that
    # matters; bodies for it are dropped by the logger, so what lands is that a refresh
    # happened, against which endpoint, with what status.
    MITM_DOMAINS = %w[googleapis.com google.com].freeze

    def default_env_vars(_session)
      {
        "AGY_CLI_HIDE_LOGO" => "1",
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => MITM_DOMAINS.join(",")
      }
    end

    def mitm_tracked_domains
      MITM_DOMAINS.dup
    end

    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    def fetch_available_models_with_source(credentials, credential: nil)
      access_token = credentials["access_token"]
      return fallback_models if access_token.blank?

      data = Antigravity::Api.models(access_token: access_token)
      model_ids = data["agentModelSorts"].to_a.flat_map do |sort|
        sort["groups"].to_a.flat_map { |group| group["modelIds"].to_a }
      end
      models = model_ids.uniq.filter_map do |model_id|
        model = data.dig("models", model_id)
        next unless model.is_a?(Hash)

        { model_id: model_id, display_name: model["displayName"].presence || model_id }
      end

      models.present? ? { models: models, source: :api } : fallback_models
    rescue StandardError => e
      Rails.logger.warn("[AntigravityCliAdapter] fetch_available_models failed: #{e.message}")
      fallback_models
    end

    # Reject credentials saved by the earlier API-key implementation before
    # launching `agy`. Those rows contain `api_key`, not an OAuth access token;
    # allowing them through would make interactive sessions fall back to login
    # and leave automatic sessions waiting indefinitely.
    def credential_preflight(runtime, container, container_id)
      details = credential_file_metadata(runtime, container_id, config_path)
      return details.merge(valid: false, error_code: "auth_file_missing") unless details[:exists]

      stdout, _stderr, status = runtime.exec(container, [ "cat", config_path ], stdout: true, stderr: true)
      return details.merge(valid: false, error_code: "auth_file_missing") unless status.to_i.zero?

      return details.merge(valid: true, error_code: nil) if auth_complete?(Array(stdout).join)

      details.merge(valid: false, error_code: "oauth_token_missing")
    end

    def session_command(mode:, prompt: nil, model: nil)
      parts = [ "agy" ]
      parts += [ "--model", Shellwords.shellescape(model) ] if model.present?
      parts << "--dangerously-skip-permissions"
      # --output-format must precede --print: `agy` treats a bare --print as taking
      # the next token as its own prompt value, so --print immediately followed by
      # --output-format silently swallows the flag as literal prompt text instead of
      # parsing it — confirmed against the real 1.1.27 binary.
      parts += [ "--output-format", "stream-json", "--print" ] if mode == "non_interactive"
      parts.join(" ")
    end

    # Antigravity writes its NDJSON stream to stdout. The base entrypoint pipes
    # stdout to terminal_output.log, which cleanup persists immediately before
    # calling this hook. Only terminal `result` events are used: step_update
    # usage is per-step and the result usage is already the cumulative run total.
    def collect_usage(terminal_session, artifacts = {})
      # The result event carries the run's cumulative total, and Accumulator.record
      # always increments — so a cleanup retry (max_attempts: 2) re-parsing the same
      # log would double every value already persisted. Once a statistic exists for
      # this session, this source has already had its say.
      return if terminal_session.usage_statistic.present?

      output = artifacts["logs/terminal_output.log"].presence || terminal_output(terminal_session)
      events = usage_events(output, terminal_session)
      return if events.empty?

      UsageStatistics::Accumulator.record(
        terminal_session: terminal_session,
        events: events,
        source: "antigravity_stream_json"
      )
    end

    def context_file_path = "#{home_dir}/.gemini/GEMINI.md"
    def skills_agent_name = "gemini-cli"
    def skills_install_path = "#{home_dir}/.gemini/skills"

    def mcp_config(servers)
      entries = servers.to_h do |server|
        config = {}
        if server.transport.to_s == "stdio"
          config["command"] = server.command if server.respond_to?(:command)
          config["args"] = mcp_stdio_args(server) if server.respond_to?(:args) && server.args.present?
          config["env"] = mcp_stdio_env(server)
        else
          config["serverUrl"] = server.url if server.url.present?
          config["headers"] = server.headers if server.headers.present?
        end
        [ MCPServer.config_key_for(server.name), config ]
      end
      { "#{home_dir}/.gemini/config/mcp_config.json" => { "mcpServers" => entries }.to_json }
    end

    def mcp_merge_strategy = :merge_json

    private

    ANSI_ESCAPE = /\e(?:\[[0-?]*[ -\/]*[@-~]|\][^\a]*(?:\a|\e\\))/.freeze

    def terminal_output(terminal_session)
      terminal_session.session_logs.find_by(name: "terminal_output.log")&.file&.read
    rescue StandardError => e
      Rails.logger.warn("[AntigravityCliAdapter] unable to read terminal output: #{e.message}")
      nil
    end

    def usage_events(output, terminal_session)
      return [] if output.blank?

      stream_model = nil
      output.each_line.filter_map do |raw_line|
        event = parse_stream_event(raw_line)
        next unless event

        stream_model ||= event.dig("init", "model") || event["model"]
        next unless event["event"] == "result"

        result = event["result"]
        usage = result.is_a?(Hash) ? result["usage"] : nil
        next unless usage.is_a?(Hash)

        input = usage["input_tokens"].to_i
        output_tokens = usage["output_tokens"].to_i
        cached = usage["cache_read_tokens"].to_i
        next if input.zero? && output_tokens.zero? && cached.zero?

        model = result["model"].presence || stream_model.presence || terminal_session.requested_model.presence ||
          default_model_for(terminal_session)
        {
          "model" => model,
          "timestamp" => terminal_session.finished_at&.to_i&.to_s,
          "tokenUsage" => {
            "inputTokens" => input,
            "outputTokens" => output_tokens,
            "cacheReadTokens" => cached,
            "cacheWriteTokens" => 0,
            "reasoningTokens" => usage["thinking_tokens"].to_i,
            "totalCents" => usage_cost_cents(model, input, output_tokens, cached)
          },
          "source" => "antigravity_stream_json"
        }
      end
    end

    def parse_stream_event(raw_line)
      line = raw_line.to_s.gsub(ANSI_ESCAPE, "").strip
      json_start = line.index("{")
      return nil unless json_start

      parsed = JSON.parse(line[json_start..])
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def default_model_for(terminal_session)
      SessionCompany.agent_credentials_for(terminal_session)
                    .find_by(agent_type: "antigravity_cli")&.default_model
    end

    def usage_cost_cents(model, input_tokens, output_tokens, cache_read_tokens)
      pricing = MODEL_PRICING[model]
      unless pricing
        Rails.logger.warn("[AntigravityCliAdapter] no configured pricing for model #{model.inspect}")
        return 0.0
      end

      cached = [ cache_read_tokens, input_tokens ].min
      uncached = input_tokens - cached
      ((uncached * pricing[:input]) + (cached * pricing[:cache_read]) +
        (output_tokens * pricing[:output])) / 10_000.0
    end

    def fallback_models
      { models: FALLBACK_MODELS, source: :fallback }
    end

    def oauth_client
      config = Settings.agents.antigravity
      return nil if config&.oauth_client_id.blank? || config.oauth_client_secret.blank?

      { id: config.oauth_client_id, secret: config.oauth_client_secret }
    end

    def server_refreshable?(credentials)
      oauth_client.present? && SERVER_REFRESHABLE_AUTH_METHODS.include?(credentials["auth_method"])
    end

    def settings
      # Omitting modelProvider selects Antigravity's OAuth-backed default
      # backend. Explicitly selecting "gemini" instead requires GEMINI_API_KEY.
      { "enableTelemetry" => false, "showTips" => false }
    end
  end
end
