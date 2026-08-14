# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "shellwords"

module Agents
  # xAI Grok CLI adapter (`@xai-official/grok`, binary `grok`).
  #
  # Config layout inside the container:
  #   ~/.grok/auth.json   — credentials, written by every login flow the CLI supports.
  #                         It is a map of auth SCOPE => entry, e.g.
  #                           { "https://accounts.x.ai/sign-in": { "key": "<token>", ... } }
  #                         for the OAuth/device-code flow, and a "xai::api_key" scope
  #                         when the user signs in with an API key instead.
  #   ~/.grok/config.toml — everything else: permission mode, folder trust, telemetry,
  #                         the pinned model, and `[mcp_servers.*]`.
  #   ~/.grok/rules/      — home-level rule files, read on every session in every
  #                         directory. This is where the Aixle session context lands.
  #   ~/.grok/skills/     — where `skills add -g -a grok` installs skills.
  #
  # Auth: the auth container runs `grok login --device-auth` (see
  # AgentBaseStrategy::AUTH_COMMANDS). The device-code flow is the only interactive
  # flow that completes without a browser on the container host: the CLI prints a URL
  # and a code, the user finishes on their own device, and the CLI writes auth.json.
  # An API key (`XAI_API_KEY`) is honoured too, but only as a credential we already
  # hold — see #default_env_vars.
  class GrokAdapter < BaseAdapter
    # The OAuth/session-token scope the CLI writes for a grok.com / accounts.x.ai login,
    # and the pseudo-scope it writes for an API-key login. Both live in the same file.
    OAUTH_SCOPE = "https://accounts.x.ai/sign-in"
    API_KEY_SCOPE = "xai::api_key"

    # The field inside a scope entry that holds the bearer token. Named `key` by the
    # CLI (its own docs read it with `jq -r '."https://accounts.x.ai/sign-in".key'`).
    TOKEN_FIELD = "key"

    # Every host the CLI talks to for auth, the model catalogue, and inference sits
    # under x.ai, so this is what the MITM proxy tracks — and what #collect_usage reads.
    MITM_DOMAIN = "x.ai"

    def self.default_config_paths
      [ "~/.grok/config.toml", "AGENTS.md" ]
    end

    def config_path
      "#{home_dir}/.grok/auth.json"
    end

    def home_dir
      "/home/grok"
    end

    # Auth files to extract at cleanup. config.toml carries no credential material —
    # we generate it — so auth.json is the whole credential.
    def auth_file_paths
      [ config_path ]
    end

    # auth.json is a map keyed by auth scope, and those keys are URLs
    # ("https://accounts.x.ai/sign-in"). The watcher resolves a required key by
    # splitting it on ".", so no scope key is addressable that way — use the
    # existence sentinel instead. The CLI writes the file only when it stores a
    # token, so "present and non-empty" is a truthful completion signal, and the
    # server-side #auth_complete? below is the stricter gate on persistence.
    def auth_required_keys
      %w[__present__]
    end

    # Server-side completion check (gates credential persistence): auth.json must
    # parse as a JSON object and at least one scope entry must carry a token.
    def auth_complete?(config_content)
      auth_scopes(parse_json(config_content)).any?
    end

    # Persist the scope map as-is: it is the CLI's own credential format and is
    # written straight back for the next session. `api_key` is lifted out as a flat
    # field because it is also injected as an env var (see #default_env_vars) and
    # because it is what the models API accepts as a bearer token.
    def extract_credentials(config_content)
      scopes = auth_scopes(parse_json(config_content))
      return {} if scopes.empty?

      credentials = { "auth" => scopes }
      api_key = scopes.dig(API_KEY_SCOPE, TOKEN_FIELD)
      credentials["api_key"] = api_key if api_key.present?
      credentials
    end

    # auth.json content for a new container: the stored scope map, unchanged.
    def generate_config(credentials, workflow_config = {})
      credentials["auth"] || {}
    end

    def config_files(credentials, workflow_config = {})
      files = { "#{home_dir}/.grok/config.toml" => generate_config_toml(workflow_config) }
      auth = generate_config(credentials, workflow_config)
      files[config_path] = auth.to_json if auth.present?
      files
    end

    # Written before `grok login --device-auth` starts (AgentAuthStrategy#before_exec)
    # so the login terminal does not self-update mid-flow and does not gate on folder
    # trust. It deliberately carries no model pin: no credential exists yet.
    def auth_setup_files
      { "#{home_dir}/.grok/config.toml" => generate_config_toml({}) }
    end

    # Session command: `grok --yolo` (documented alias of `--always-approve`, i.e.
    # permission mode `bypassPermissions`) — the container is the sandbox.
    # A prompt is appended by AgentSessionStrategy from the AGENT_PROMPT env var.
    def session_command(mode:, prompt: nil, model: nil)
      model ? "grok --yolo --model #{Shellwords.shellescape(model)}" : "grok --yolo"
    end

    # Context file: a home-level rule file. `~/.grok/rules/*.md` is scanned on every
    # session regardless of the working directory (and regardless of whether it is a
    # git repo), which keeps /workspace clean — unlike AGENTS.md, which would have to
    # live in the repo the user is working on.
    def context_file_path
      "#{home_dir}/.grok/rules/aixle-session-context.md"
    end

    # skills.sh agent id for `npx skills add --agent grok`.
    def skills_agent_name
      "grok"
    end

    # Where `skills add -g -a grok` puts a skill.
    def skills_install_path
      "#{home_dir}/.grok/skills"
    end

    # MCP config: `[mcp_servers.<key>]` tables appended to ~/.grok/config.toml, keyed by
    # the same protocol key every other runtime writes (MCPServer.config_key_for), so a
    # server's tool namespace is identical across runtimes. STDIO servers take
    # command/args/env; remote servers take url/headers — the CLI infers the transport
    # from which of the two is present, so there is no type field.
    def mcp_config(servers)
      sections = servers.map do |s|
        lines = [ "[mcp_servers.#{toml_string(MCPServer.config_key_for(s.name))}]" ]
        if s.transport.to_s == "stdio"
          lines << "command = #{toml_string(s.command)}" if s.respond_to?(:command)
          if s.respond_to?(:args) && s.args.present?
            lines << "args = [#{mcp_stdio_args(s).map { |a| toml_string(a) }.join(', ')}]"
          end
          env = mcp_stdio_env(s)
          lines << "env = { #{env.map { |k, v| "#{toml_string(k)} = #{toml_string(v)}" }.join(', ')} }" if env.present?
        else
          lines << "url = #{toml_string(s.url)}" if s.url.present?
          if s.headers.present? && s.headers.any?
            lines << "headers = { #{s.headers.map { |k, v| "#{toml_string(k)} = #{toml_string(v)}" }.join(', ')} }"
          end
        end
        lines.join("\n")
      end

      { "#{home_dir}/.grok/config.toml" => "# MCP Servers (auto-generated)\n#{sections.join("\n\n")}\n" }
    end

    def mcp_merge_strategy
      :append_toml
    end

    # Render a value as a TOML basic string with the required escapes, so a name,
    # header or arg containing a quote or backslash cannot corrupt config.toml.
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

    # Env for the MITM proxy, which is where session usage comes from (see
    # #collect_usage), plus the API key when the credential is an API-key login.
    def default_env_vars(session)
      env = {
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => MITM_DOMAIN
      }

      # Inject the API key from the credential of THIS session's company: keys are per
      # company so the vendor bill lands on the company that ran the session.
      credential = SessionCompany.agent_credentials_for(session).find_by(agent_type: "grok")
      api_key = credential&.config_data&.dig("api_key")
      env["XAI_API_KEY"] = api_key if api_key.present?

      env
    end

    # A stray XAI_API_KEY outranks a stored session token in the CLI's credential
    # resolution, so a key left in the environment by another source would silently
    # bill a different account than the one the user authenticated. Drop it whenever
    # this credential is NOT an API-key login (when it is, #default_env_vars puts the
    # right value back).
    def conflicting_env_keys(credentials)
      credentials.is_a?(Hash) && credentials["api_key"].present? ? [] : %w[XAI_API_KEY]
    end

    def mitm_tracked_domains
      [ MITM_DOMAIN ]
    end

    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # Soonest expiry across the scope entries that carry one, in epoch ms, so
    # AgentCredential#expires_at reflects a Grok session token (they are short-lived —
    # the CLI falls back to a 30-day lifetime only when the server sends no expiry).
    # Nothing recognisable => nil, which is the same as "no expiry known" and leaves
    # the credential permanently active, exactly as before this runtime existed.
    def token_expires_at(credentials)
      return nil unless credentials.is_a?(Hash)

      auth_scopes(credentials["auth"])
        .values
        .filter_map { |entry| expiry_ms(entry["expires_at"]) }
        .min
    end

    # =================================================================
    # Available Models
    # =================================================================

    # The xAI model catalogue, which also carries per-token prices (see #price_sheet).
    MODELS_URL = "https://api.x.ai/v1/language-models"

    # Used only when the catalogue is unreachable or the credential is a session token
    # the public API declines. Deliberately minimal: `grok-4.5` is what the CLI itself
    # reports as its default model, and the other two are the current coding models in
    # the published catalogue. The live call is the source of truth.
    FALLBACK_MODELS = [
      { model_id: "grok-4.5", display_name: "grok-4.5", description: "Grok 4.5 — the Grok CLI default model" },
      { model_id: "grok-4.6", display_name: "grok-4.6", description: "Grok 4.6 — the model behind Grok Build" },
      { model_id: "grok-code-fast-1", display_name: "grok-code-fast-1", description: "Fast, low-cost coding model" }
    ].freeze

    MODEL_DESCRIPTION_LIMIT = 120

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    def fetch_available_models_with_source(credentials, credential: nil)
      catalog = fetch_model_catalog(credentials)
      return { models: FALLBACK_MODELS, source: :fallback } if catalog.blank?

      models = catalog.filter_map do |model|
        model_id = (model["id"] || model["name"]).to_s
        next if model_id.blank?

        {
          model_id: model_id,
          display_name: model_id,
          description: model_description(model).truncate(MODEL_DESCRIPTION_LIMIT)
        }
      end

      models.present? ? { models: models, source: :api } : { models: FALLBACK_MODELS, source: :fallback }
    end

    # =================================================================
    # Usage Collection
    # =================================================================

    # Grok CLI's own OpenTelemetry export cannot be correlated back to an Aixle
    # session: its resource attributes are a fixed, audited set (it ignores
    # OTEL_RESOURCE_ATTRIBUTES outright) and out-of-schema attribute keys are dropped
    # at export, so `terminal_session_token` — the only thing UsageStatisticsService
    # matches on — can never reach the collector. Usage therefore comes from the MITM
    # log at cleanup, the same source CursorCli and Codex fall back to.
    #
    # Model traffic goes to api.x.ai over HTTPS and the responses are OpenAI-shaped, so
    # each completion carries a `usage` object. Cost is priced from the xAI catalogue,
    # whose per-token prices are quoted in cents per 10^8 tokens.
    def collect_usage(terminal_session, artifacts = {})
      mitm_log = artifacts["logs/http.log"]
      events = extract_events_from_mitm(mitm_log)

      if events.empty?
        Rails.logger.warn("[GrokAdapter] No usage events in MITM log for session #{terminal_session.id}")
        return
      end

      apply_costs!(events, terminal_session)
      persist_usage_statistic(terminal_session, events)
    end

    private

    # Scope => entry pairs that actually carry a token. Anything that is not a hash
    # with a non-blank token field is dropped, so a partially-written or unrelated
    # JSON file never counts as a completed login.
    def auth_scopes(parsed)
      return {} unless parsed.is_a?(Hash)

      parsed.each_with_object({}) do |(scope, entry), scopes|
        next unless entry.is_a?(Hash) && entry[TOKEN_FIELD].present?

        scopes[scope.to_s] = entry
      end
    end

    # The bearer token to authenticate an xAI API call with: an API key when the user
    # signed in with one, otherwise the OAuth session token (which the public API may
    # decline — callers treat a failure as "fall back", never as an error).
    def bearer_token(credentials)
      return nil unless credentials.is_a?(Hash)
      return credentials["api_key"] if credentials["api_key"].present?

      scopes = auth_scopes(credentials["auth"])
      scopes.dig(API_KEY_SCOPE, TOKEN_FIELD) ||
        scopes.dig(OAUTH_SCOPE, TOKEN_FIELD) ||
        scopes.values.first&.dig(TOKEN_FIELD)
    end

    # Accepts the shapes an expiry can plausibly arrive in and normalises to epoch ms:
    # an ISO8601 timestamp, epoch seconds, or epoch milliseconds. Anything else is nil.
    def expiry_ms(value)
      return nil if value.blank?

      case value
      when Numeric, /\A\d+\z/
        seconds_or_ms = value.to_i
        # An epoch in seconds is ~1.7e9; the same instant in milliseconds is ~1.7e12.
        seconds_or_ms > 100_000_000_000 ? seconds_or_ms : seconds_or_ms * 1000
      when String
        parsed = Time.zone.parse(value)
        parsed && (parsed.to_f * 1000).round
      end
    rescue ArgumentError, TypeError
      nil
    end

    def model_description(model)
      modalities = Array(model["input_modalities"] || model["inputModalities"]).map(&:to_s).map(&:downcase)
      context = model["max_prompt_length"] || model["maxPromptLength"]

      parts = []
      parts << "input: #{modalities.join(', ')}" if modalities.present?
      parts << "context: #{context} tokens" if context.present?
      parts.join(" · ")
    end

    def fetch_model_catalog(credentials)
      token = bearer_token(credentials)
      return nil if token.blank?

      uri = URI(MODELS_URL)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
      return nil unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      models = body["models"] || body["data"]
      models.is_a?(Array) ? models : nil
    rescue StandardError => e
      Rails.logger.warn("[GrokAdapter] model catalogue fetch failed: #{e.message}")
      nil
    end

    # =========================================================================
    # MITM log parsing
    # =========================================================================

    # xAI response bodies are OpenAI-shaped, and Grok speaks both wire formats:
    # Chat Completions (`prompt_tokens`/`completion_tokens`) and the Responses API
    # (`input_tokens`/`output_tokens`). Both are matched, because which one a given
    # CLI build uses is not something this adapter should depend on.
    USAGE_FIELD_ALIASES = {
      input_tokens: %w[prompt_tokens input_tokens],
      output_tokens: %w[completion_tokens output_tokens],
      cache_read_tokens: %w[cached_tokens cached_prompt_text_tokens],
      reasoning_tokens: %w[reasoning_tokens]
    }.freeze

    def extract_events_from_mitm(log_content)
      return [] if log_content.blank?

      log_content.each_line.filter_map do |line|
        entry = JSON.parse(line.strip)
        next unless entry["direction"] == "response"
        next unless entry["host"].to_s.end_with?(MITM_DOMAIN)

        body = decode_body(entry)
        next if body.blank?

        usage_event(body, entry["ts"])
      rescue JSON::ParserError
        next
      end
    end

    # A streamed response's `usage` object arrives in the final chunk and the logged
    # body may be a truncated tail, so the counts are pulled out by pattern rather
    # than by parsing the whole body — the same approach the Codex adapter uses.
    def usage_event(text, timestamp)
      counts = USAGE_FIELD_ALIASES.transform_values do |aliases|
        aliases.filter_map { |field| text[/"#{field}"\s*:\s*(\d+)/, 1]&.to_i }.max
      end
      return nil if counts[:input_tokens].nil? && counts[:output_tokens].nil?

      output_tokens = counts[:output_tokens].to_i
      # Reasoning tokens are billed as completion tokens but the API also reports them
      # inside completion_tokens, so they are recorded, not added.
      {
        "model" => text[/"model"\s*:\s*"([^"]+)"/, 1],
        "timestamp" => timestamp,
        "tokenUsage" => {
          "inputTokens" => counts[:input_tokens].to_i,
          "outputTokens" => output_tokens,
          "cacheReadTokens" => counts[:cache_read_tokens].to_i,
          "cacheWriteTokens" => 0,
          "reasoningTokens" => counts[:reasoning_tokens].to_i,
          "totalCents" => 0.0
        },
        "source" => "mitm"
      }
    end

    def decode_body(entry)
      body = entry["body"].to_s
      return "" if body.blank?

      entry["body_encoding"] == "base64" ? Base64.decode64(body).force_encoding("UTF-8") : body
    rescue ArgumentError
      ""
    end

    # =========================================================================
    # Cost
    # =========================================================================

    # xAI quotes per-token prices in cents per 10^8 tokens, so cents = tokens * price
    # / 1e8. Uncached input, cached input and output are priced separately.
    PRICE_SCALE = 100_000_000.0

    def apply_costs!(events, terminal_session)
      prices = price_sheet(terminal_session)
      return if prices.blank?

      events.each do |event|
        price = prices[event["model"]]
        next if price.blank?

        usage = event["tokenUsage"]
        cached = usage["cacheReadTokens"].to_i
        uncached_input = [ usage["inputTokens"].to_i - cached, 0 ].max
        cents = (uncached_input * price[:prompt] + cached * price[:cached] + usage["outputTokens"].to_i * price[:completion]) / PRICE_SCALE
        usage["totalCents"] = cents.round(6)
      end
    end

    # model id (and every alias it answers to) => per-token prices, from the xAI
    # catalogue. Fetched with the session's company credential, because that is the
    # account whose price list applies.
    def price_sheet(terminal_session)
      credential = SessionCompany.agent_credentials_for(terminal_session).find_by(agent_type: "grok")
      catalog = fetch_model_catalog(credential&.config_data || {})
      return {} if catalog.blank?

      catalog.each_with_object({}) do |model, sheet|
        prices = {
          prompt: model["prompt_text_token_price"].to_f,
          cached: model["cached_prompt_text_token_price"].to_f,
          completion: model["completion_text_token_price"].to_f
        }
        next if prices.values.all?(&:zero?)

        ([ model["id"] || model["name"] ] + Array(model["aliases"])).compact.each do |name|
          sheet[name.to_s] = prices
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[GrokAdapter] price sheet fetch failed: #{e.message}")
      {}
    end

    def persist_usage_statistic(terminal_session, events)
      totals = aggregate_events(events)
      models = events.filter_map { |event| event["model"] }.uniq

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
        "[GrokAdapter] Session #{terminal_session.id} usage: #{events.size} events, " \
        "in=#{totals[:input_tokens]} out=#{totals[:output_tokens]} " \
        "cache_r=#{totals[:cache_read_tokens]} models=#{models.join(', ')}"
      )
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

    # =========================================================================
    # config.toml
    # =========================================================================

    # Everything the CLI would otherwise stop and ask about, decided up front:
    #   * always-approve — the container is the sandbox, so tool calls are not gated
    #     (`--yolo` on the session command sets the same mode; this covers the login
    #     terminal and any CLI the user starts by hand).
    #   * folder trust off — un-gates repo-local MCP/LSP/hooks so no session blocks on
    #     "Trust the authors of this folder?".
    #   * auto-update off — the image pins the CLI version; a self-update inside a
    #     container would drift from it and be lost on the next start anyway.
    #   * telemetry off — nothing about a customer's session goes to xAI analytics.
    def generate_config_toml(workflow_config)
      model = workflow_config[:model]
      toml = +""
      toml << <<~TOML
        [cli]
        auto_update = false

        [ui]
        permission_mode = "always-approve"

        [folder_trust]
        enabled = false

        [features]
        telemetry = false

      TOML
      toml << "[models]\ndefault = #{toml_string(model)}\n" if model.present?
      toml
    end
  end
end
