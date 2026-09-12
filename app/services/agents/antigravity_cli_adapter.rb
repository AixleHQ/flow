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

    # Where `agy` records that its first-run wizard is done. Confirmed against the
    # real binary by completing the wizard in a container and diffing the whole
    # filesystem: the colour-scheme picker and the "Terms of Service & Data Use"
    # screen are gated on this file alone — nothing in settings.json, the state
    # proto, the installation id or the summaries database moves when they are
    # answered. Without it every session opens on the wizard and waits for a
    # keypress, which an automatic session never sends.
    ONBOARDING_PATH = ".gemini/antigravity-cli/cache/onboarding.json"

    WORKSPACE = "/workspace"

    def self.default_config_paths
      [ "~/.gemini/antigravity-cli/settings.json", "~/.gemini/config/mcp_config.json", "GEMINI.md" ]
    end

    def home_dir = "/home/antigravity"
    def config_path = "#{home_dir}/#{OAUTH_TOKEN_PATH}"

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
      first_run_files.merge(config_path => generate_config(credentials).to_json)
    end

    # Written before auth starts so the auth terminal already has telemetry/tips
    # disabled and the first-run wizard out of the way when `agy` itself launches
    # (see AgentAuthStrategy#before_exec). Seeding the wizard as done does not
    # skip the login itself — verified against the real binary: with no token
    # file present `agy` still opens on its "Select login method" prompt.
    def auth_setup_files
      first_run_files
    end

    # Hosts the model traffic goes to. Both spellings are listed because the
    # proxy addon matches a tracked domain or a subdomain of it, and
    # `daily-cloudcode-pa.googleapis.com` — which the binary calls in practice —
    # is neither of `cloudcode-pa.googleapis.com`. Google's telemetry sink
    # (`play.googleapis.com/log`) is deliberately not tracked.
    MITM_DOMAINS = %w[
      cloudcode-pa.googleapis.com
      daily-cloudcode-pa.googleapis.com
      aicode.googleapis.com
    ].freeze

    def default_env_vars(_session)
      {
        "AGY_CLI_HIDE_LOGO" => "1",
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => MITM_DOMAINS.join(",")
      }
    end

    def mitm_tracked_domains = MITM_DOMAINS.dup

    def session_log_paths = super + %w[/var/log/mitm/http.log]

    # Reject credentials saved by the earlier API-key implementation before
    # launching `agy`. Those rows contain `api_key`, not an OAuth access token;
    # allowing them through would make interactive sessions fall back to login
    # and leave automatic sessions waiting indefinitely.
    def credential_preflight(runtime, container, _container_id)
      stdout, _stderr, status = runtime.exec(container, [ "cat", config_path ], stdout: true, stderr: true)
      return { valid: false, error_code: "auth_file_missing" } unless status.to_i.zero?

      return { valid: true, error_code: nil } if auth_complete?(Array(stdout).join)

      { valid: false, error_code: "oauth_token_missing" }
    end

    # Automatic sessions run the same TUI as interactive ones, like every other
    # adapter here — they finish by calling finish_session/fail_session, not by
    # exiting a one-shot print run.
    #
    # The trailing `-i` is load-bearing. AgentSessionStrategy#launch_agent_in_tmux
    # appends the prompt as a positional argument, and `agy` — unlike claude,
    # codex, cursor and gemini — refuses one outright: `Error: unexpected argument
    # "…". Prompts are read only from -p/--print, -i/--prompt-interactive, or
    # stdin`. Ending the command with `-i` makes the appended prompt that flag's
    # value, which starts the TUI on that prompt and keeps the session going.
    def session_command(mode:, prompt: nil, model: nil)
      parts = [ "agy" ]
      parts += [ "--model", Shellwords.shellescape(model) ] if model.present?
      parts << "--dangerously-skip-permissions"
      parts << "-i" if mode == "non_interactive" && prompt.present?
      parts.join(" ")
    end

    # =================================================================
    # Available Models
    # =================================================================

    # What `agy models` itself calls (captured off the wire through the session
    # image's own MITM proxy). The request body is a bare `{}`; the response
    # carries every model the account can see, plus the ordering the CLI shows.
    MODELS_URL = "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"

    # Not decoration: this endpoint gates on the client User-Agent. The exact
    # same Bearer token answers 403 with curl's default agent and 200 with an
    # `antigravity/cli/<version> (aidev_client…)` one — the `aidev_client` token
    # alone is not enough, the `antigravity/cli/<version>` prefix is what is
    # checked. `daily-cloudcode-pa.googleapis.com` (what the binary happened to
    # call) and the stable host above return byte-identical payloads.
    MODELS_USER_AGENT = "antigravity/cli/1.1.27 (aidev_client; os_type=linux; arch=amd64; auth_method=consumer)"

    # The 14 ids Antigravity offers for agent sessions, in its own order, as of
    # 2026-09-12. The API returns 33 models; the rest are internal (tab
    # completion, chat experiments, commit messages) and `--model` is not meant
    # to take them, so the list here mirrors what the live call filters down to.
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
      { model_id: "gemini-pro-agent", display_name: "Gemini 3.1 Pro (High)" },
      { model_id: "gemini-3.1-pro-low", display_name: "Gemini 3.1 Pro (Low)" },
      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6 (Thinking)" },
      { model_id: "claude-opus-4-6-thinking", display_name: "Claude Opus 4.6 (Thinking)" },
      { model_id: "gpt-oss-120b-medium", display_name: "GPT-OSS 120B (Medium)" }
    ].freeze

    # Straight from the same response's `deprecatedModelIds`, which maps a
    # retired id to the one that replaces it.
    RETIRED_MODEL_REPLACEMENTS = { "gemini-3.1-pro-high" => "gemini-pro-agent" }.freeze

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    # The stored access token is short-lived (about an hour) and nothing renews
    # it on our side — `agy` refreshes in its own container and we never read
    # that back — so an expired token is the normal case, not an error worth
    # surfacing. Every failure path falls back to the pinned list, which is what
    # keeps the model picker populated instead of empty.
    def fetch_available_models_with_source(credentials, credential: nil)
      token = credentials.is_a?(Hash) ? credentials["access_token"] : nil
      return { models: FALLBACK_MODELS, source: :fallback } if token.blank?

      response = request_models(token)
      return { models: FALLBACK_MODELS, source: :fallback } unless response.is_a?(Net::HTTPSuccess)

      models = agent_models(JSON.parse(response.body))
      models.present? ? { models: models, source: :api } : { models: FALLBACK_MODELS, source: :fallback }
    rescue StandardError => e
      Rails.logger.warn("[AntigravityCliAdapter] fetch_available_models failed: #{e.message}")
      { models: FALLBACK_MODELS, source: :fallback }
    end

    # =================================================================
    # Usage collection
    # =================================================================

    # There is no telemetry path to read: the binary carries no
    # `OTEL_EXPORTER_OTLP_*` support and no `otlpEndpoint` setting, only Google's
    # own client pointed at `play.googleapis.com/log`, so nothing can be
    # re-pointed at our collector. The MITM log is the only source that covers
    # interactive and automatic sessions alike, and it does work against this
    # CLI: `agy` is a Go binary, which honours HTTPS_PROXY and SSL_CERT_FILE, so
    # the proxy half of the session image's logger captures it (the
    # `http2-logger.js` half only patches Node and never sees it) — verified by
    # capturing a full `fetchAvailableModels` round trip through it.
    def collect_usage(terminal_session, artifacts = {})
      if terminal_session.usage_statistic.present?
        Rails.logger.info("[AntigravityCliAdapter] Session #{terminal_session.id}: usage already recorded, skipping")
        return
      end

      events = extract_events_from_mitm(artifacts["logs/http.log"])
      if events.empty?
        Rails.logger.warn("[AntigravityCliAdapter] No usage events in MITM log for session #{terminal_session.id}")
        return
      end

      UsageStatistics::Accumulator.record(terminal_session: terminal_session, events: events, source: "mitm")
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

    # Same rule the proxy addon filters on (docker/base/logger/mitm_logger.py
    # ::_should_log): the host is the tracked domain itself or a subdomain of it.
    # A bare suffix test would also accept a lookalike host, which must never be
    # read as vendor traffic.
    def tracked_host?(host)
      host = host.to_s.downcase
      return false if host.blank?

      MITM_DOMAINS.any? { |domain| host == domain || host.end_with?(".#{domain}") }
    end

    def extract_events_from_mitm(log_content)
      return [] if log_content.blank?

      log_content.each_line.filter_map do |line|
        entry = JSON.parse(line.strip)
        next unless entry["direction"] == "response"
        next unless tracked_host?(entry["host"])

        body = decode_body(entry)
        next if body.blank?

        usage_event(body, entry["ts"])
      rescue JSON::ParserError
        next
      end
    end

    # Counts are pulled out by pattern rather than by parsing the whole body: a
    # streamed response's final chunk is where they arrive, and the logged body
    # can be a truncated tail — the same approach Codex and Grok take.
    #
    # The field names are Google's `usageMetadata` block, which is what every
    # other client of this Code Assist backend (Gemini CLI included) receives.
    # This has NOT been confirmed against a live Antigravity completion: the
    # account available for testing fails Antigravity's eligibility check
    # ("not currently available in your location"), so no completion call
    # reaches the wire at all. The capture side is verified; these field names
    # are the part still to confirm against a real run.
    def usage_event(text, timestamp)
      prompt_tokens = count_field(text, "promptTokenCount")
      candidate_tokens = count_field(text, "candidatesTokenCount")
      return nil if prompt_tokens.nil? && candidate_tokens.nil?

      thoughts = count_field(text, "thoughtsTokenCount").to_i

      {
        "model" => text[/"modelVersion"\s*:\s*"([^"]+)"/, 1] || text[/"model"\s*:\s*"([^"]+)"/, 1],
        "timestamp" => timestamp,
        "tokenUsage" => {
          "inputTokens" => prompt_tokens.to_i,
          # Google reports thinking tokens outside candidatesTokenCount but bills
          # them as output, so they are added here rather than only recorded.
          "outputTokens" => candidate_tokens.to_i + thoughts,
          "cacheReadTokens" => count_field(text, "cachedContentTokenCount").to_i,
          "cacheWriteTokens" => 0,
          "reasoningTokens" => thoughts,
          # Antigravity bills against a subscription quota, not per token, and
          # Google publishes no per-token price for this backend — so tokens are
          # recorded and cost deliberately is not invented.
          "totalCents" => 0.0
        },
        "source" => "mitm"
      }
    end

    def count_field(text, field)
      text[/"#{field}"\s*:\s*(\d+)/, 1]&.to_i
    end

    def decode_body(entry)
      body = entry["body"].to_s
      return "" if body.blank?

      entry["body_encoding"] == "base64" ? Base64.decode64(body).force_encoding("UTF-8") : body
    rescue ArgumentError
      ""
    end

    def request_models(token)
      uri = URI(MODELS_URL)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["User-Agent"] = MODELS_USER_AGENT
      req["Content-Type"] = "application/json"
      req.body = "{}"

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(req)
      end
    end

    # `agentModelSorts` is the CLI's own answer to "which models may an agent
    # session run, and in what order" — the same 14 ids `agy models` prints —
    # while `models` is the full catalogue keyed by id. Take the order from the
    # first, the display names from the second.
    def agent_models(payload)
      catalogue = payload["models"]
      return [] unless catalogue.is_a?(Hash)

      sorted_ids(payload).filter_map do |id|
        entry = catalogue[id]
        next if entry.nil?

        display_name = entry["displayName"].presence || id
        { model_id: id, display_name: display_name, description: context_description(entry) }.compact
      end
    end

    def sorted_ids(payload)
      Array(payload["agentModelSorts"]).flat_map do |sort|
        Array(sort["groups"]).flat_map { |group| Array(group["modelIds"]) }
      end.uniq
    end

    def context_description(entry)
      max_tokens = entry["maxTokens"].to_i
      return nil unless max_tokens.positive?

      size = if max_tokens >= 1_000_000
        "#{(max_tokens / 1_000_000.0).round}M"
      elsif max_tokens >= 1_000
        "#{(max_tokens / 1_000.0).round}K"
      else
        max_tokens.to_s
      end
      "#{size} token context"
    end

    # Everything `agy` would otherwise stop and ask a human for on a first run in
    # a fresh container: the colour scheme, the data-use consent, and folder
    # trust. All three are answered here so a session opens straight on the
    # prompt.
    def first_run_files
      {
        "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json,
        "#{home_dir}/#{ONBOARDING_PATH}" => onboarding_state.to_json
      }
    end

    def settings
      # Omitting modelProvider selects Antigravity's OAuth-backed default
      # backend. Explicitly selecting "gemini" instead requires GEMINI_API_KEY.
      #
      # trustedWorkspaces is the shape `agy` itself writes when a user answers
      # "Yes, I trust this folder"; pre-seeding it skips that prompt.
      { "enableTelemetry" => false, "showTips" => false, "trustedWorkspaces" => [ WORKSPACE ] }
    end

    # `consumerOnboardingComplete` is the half that matters for an account signed
    # in with plain Google OAuth (`auth_method: "consumer"`); the enterprise flag
    # is written as false by the CLI itself in that case, and is kept here so the
    # file matches what a real completed wizard leaves behind.
    def onboarding_state
      {
        "consumerOnboardingComplete" => true,
        "enterpriseOnboardingComplete" => false,
        "onboardingComplete" => true
      }
    end
  end
end
