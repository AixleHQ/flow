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

    # Built-in Claude Code tools (always allowed). DesignSync is an aixle-provided
    # tool that must be allow-listed so it runs without a prompt.
    BUILTIN_TOOLS = %w[Task Bash Glob Grep LS Read Edit MultiEdit Write WebFetch WebSearch DesignSync].freeze

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

    # /design-login layers a `designOauth` block onto an EXISTING Claude login. It is
    # the one "design" concept in the codebase — the AgentAuthStrategy is generic and
    # only sees an opaque `kind`; everything design-specific lives in these overrides.
    DESIGN_KIND = "design"

    # Seed the user's existing base login (minus any designOauth) so the CLI starts
    # authenticated; the session then only adds the fresh designOauth block. Stripping
    # designOauth matters on RECONNECT — otherwise the token the watcher waits for is
    # present from the start and completes instantly.
    def auth_setup_files_for(kind, current_config = nil)
      return super unless kind == DESIGN_KIND

      config_files((current_config || {}).except("designOauth"))
    end

    # Wait for the design block specifically (the base token is injected up-front).
    def auth_required_keys_for(kind)
      kind == DESIGN_KIND ? %w[designOauth.accessToken] : super
    end

    def auth_complete_for?(kind, config_content)
      return super unless kind == DESIGN_KIND

      parse_json(config_content).dig("designOauth", "accessToken").present?
    end

    # Launch the CLI already running /design-login (the prompt is passed on the command
    # line as ONE command, so there's no delay before it appears). The CLI is already
    # logged in via the seeded creds; the user just approves in the browser.
    def auth_launch_commands_for(kind)
      kind == DESIGN_KIND ? [ "claude /design-login" ] : super
    end

    # Design only ADDS the freshly-minted designOauth to the existing credential. It
    # must NOT re-capture the base from the container: the base was injected there, and
    # a full re-scrape would resurrect a stale base login (e.g. an old claudeAiOauth)
    # next to the real one → Claude's "Both claude.ai and /login managed key set".
    def reconcile_captured_credentials(kind, current, captured)
      return super unless kind == DESIGN_KIND

      design = captured["designOauth"]
      return current || {} unless design.is_a?(Hash) && design["accessToken"].present?

      (current || {}).merge("designOauth" => design)
    end

    # Soonest OAuth-token expiry (epoch ms) across all present blocks
    # (claudeAiOauth + designOauth), or nil if none carry one. Used to (a) populate
    # agent_credentials.expires_at and (b) drive the proactive-refresh sweep so we
    # fire when whichever block expires first is near expiry.
    def token_expires_at(credentials)
      OAUTH_BLOCKS.filter_map { |b| credentials.dig(b, "expiresAt") }.map(&:to_i).min
    end

    # Claude stores two independently-rotating OAuth blocks: claudeAiOauth (base login)
    # and designOauth (/design-login). Merge each block on its own expiry so that
    # (a) adding designOauth isn't skipped just because claudeAiOauth didn't change, and
    # (b) a session without design access never wipes a stored designOauth.
    OAUTH_BLOCKS = %w[claudeAiOauth designOauth].freeze

    # Proactive server-side token refresh (Temporal sweep).
    REFRESH_MARGIN_MS = 15 * 60 * 1000 # refresh a block if it expires within 15 min (or already expired)
    OAUTH_TOKEN_URL   = "https://platform.claude.com/v1/oauth/token"
    # Base (claude.ai) login client_id. Prefer Settings; fall back to the known public client id.
    BASE_OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    def merge_refreshed_credentials(current, incoming)
      merged = current.merge(incoming) # incoming wins for scalar keys (userID, oauthAccount, primaryApiKey, ...)
      OAUTH_BLOCKS.each do |block|
        picked = freshest_oauth_block(current[block], incoming[block])
        if picked.present?
          merged[block] = picked
        else
          merged.delete(block)
        end
      end
      merged
    end

    # Proactively refresh any OAuth block within the refresh margin, server-side.
    # Each block (claudeAiOauth base login + designOauth) rotates independently, so
    # we refresh only the blocks that are near expiry and persist under a row lock
    # via merge_refreshed_credentials + from_artifacts so a concurrent live session's
    # cleanup can't clobber the rotated token.
    # @param credential [AgentCredential]
    # @return [Hash] { status: :refreshed | :not_needed | :error, detail: String | nil }
    def refresh!(credential)
      current = credential.config_data
      now_ms  = (Time.current.to_f * 1000).to_i
      refreshed_blocks = {}
      error = nil

      OAUTH_BLOCKS.each do |block_name|
        block = current[block_name]
        next unless block.is_a?(Hash) && block["refreshToken"].present?

        exp = block["expiresAt"].to_i
        # refresh if expired or within the margin
        next unless exp.positive? && (exp - now_ms) <= REFRESH_MARGIN_MS

        client_id = block_name == "designOauth" ? block["clientId"] : base_oauth_client_id
        new_block = request_oauth_refresh(client_id: client_id, refresh_token: block["refreshToken"],
                                          previous: block, now_ms: now_ms)
        if new_block
          refreshed_blocks[block_name] = new_block
        else
          error ||= "#{block_name} refresh failed"
        end
      end

      return { status: :error,      detail: error } if refreshed_blocks.empty? && error
      return { status: :not_needed, detail: nil }   if refreshed_blocks.empty?

      credential.with_lock do
        fresh    = credential.config_data
        incoming = fresh.merge(refreshed_blocks)                # only the blocks we refreshed change
        merged   = merge_refreshed_credentials(fresh, incoming) # existing per-block freshest guard
        AgentCredential.from_artifacts(credential.user_id, "claude_code", merged) if merged != fresh
      end

      { status: :refreshed, detail: error } # partial failure (one block ok, one failed) still counts as refreshed
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice(
        "oauthAccount",          # OAuth account metadata (.claude.json)
        "primaryApiKey",         # API key (.claude.json, platform.claude.com path)
        "customApiKeyResponses", # approved/rejected API keys (.claude.json)
        "userID",                # user identifier (.claude.json)
        "claudeAiOauth",         # OAuth tokens (.claude/.credentials.json, claude.ai path)
        "designOauth"            # design tokens from /design-login (.credentials.json): user:design:read/write
      ).compact
    end

    # Generate ~/.claude.json content. Excludes claudeAiOauth + designOauth
    # (both live in .credentials.json, never in .claude.json).
    def generate_config(credentials, workflow_config = {})
      {
        # Credentials from database (API-key path fields, OAuth account metadata, userID, etc.)
        **credentials.except("claudeAiOauth", "designOauth"),

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

      # .credentials.json carries the claude.ai OAuth token and, if the user has run
      # /design-login, the separate designOauth token (user:design:read/write). Both
      # are written into the same file, mirroring Claude Code's own layout.
      creds_file = {}
      oauth = credentials["claudeAiOauth"]
      creds_file["claudeAiOauth"] = oauth if oauth.is_a?(Hash) && oauth["accessToken"].present?
      design = credentials["designOauth"]
      creds_file["designOauth"] = design if design.is_a?(Hash) && design["accessToken"].present?
      files["#{home_dir}/.claude/.credentials.json"] = creds_file.to_json if creds_file.any?

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
          entry["args"] = mcp_stdio_args(s) if s.respond_to?(:args)
          entry["env"] = mcp_stdio_env(s)
        else
          entry["url"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        mcp_servers[MCPServer.config_key_for(s.name)] = entry
      end
      { "/workspace/.mcp.json" => { "mcpServers" => mcp_servers }.to_json }
    end

    # Fetch available models from Anthropic API.
    # Requires API key auth (OAuth accounts may not have access).
    ANTHROPIC_MODELS_URL = "https://api.anthropic.com/v1/models"

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    # Fetch the model list using whichever auth the credential carries:
    #   - primaryApiKey            → x-api-key (platform.claude.com API key path)
    #   - claudeAiOauth.accessToken → Authorization: Bearer + oauth beta header (claude.ai OAuth path)
    # OAuth support matters because claude.ai logins have no API key, so without
    # it those users would always fall back to the hardcoded (stale) list.
    def fetch_available_models_with_source(credentials, credential: nil)
      api_key = credentials["primaryApiKey"]
      oauth_token = credentials.dig("claudeAiOauth", "accessToken")

      models =
        if api_key.present?
          fetch_models_via_api(api_key: api_key)
        elsif oauth_token.present?
          fetch_models_via_api(oauth_token: oauth_token)
        else
          []
        end

      if models.present?
        { models: models, source: :api }
      else
        { models: FALLBACK_CLAUDE_MODELS, source: :fallback }
      end
    rescue StandardError => e
      Rails.logger.warn("[ClaudeCodeAdapter] fetch_available_models failed: #{e.message}")
      { models: FALLBACK_CLAUDE_MODELS, source: :fallback }
    end

    # Safety net used only when the live API is unreachable or the token lacks
    # model-list access. Kept current so even the fallback isn't badly stale.
    FALLBACK_CLAUDE_MODELS = [
      { model_id: "claude-opus-4-8", display_name: "Claude Opus 4.8", description: "Most capable model" },
      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6", description: "Best balance of speed and intelligence" },
      { model_id: "claude-opus-4-7", display_name: "Claude Opus 4.7", description: "Highly autonomous, long-horizon work" },
      { model_id: "claude-opus-4-6", display_name: "Claude Opus 4.6", description: "Advanced reasoning" },
      { model_id: "claude-haiku-4-5", display_name: "Claude Haiku 4.5", description: "Fastest model" }
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
        "OTEL_RESOURCE_ATTRIBUTES" => resource_attributes,
        # MCP server startup timeout (ms). Default 90s — stdio servers need time for pipx/npx cold start.
        "MCP_TIMEOUT" => Settings.agents.mcp.startup_timeout_ms.to_s
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

    # Base-login client id, from Settings when configured, else the known public id.
    def base_oauth_client_id
      Settings.agents.oauth&.base_client_id.presence || BASE_OAUTH_CLIENT_ID
    rescue StandardError
      BASE_OAUTH_CLIENT_ID
    end

    # Exchange a refresh token for a fresh OAuth block via the token endpoint.
    # Returns the rebuilt block (accessToken/refreshToken/expiresAt/scopes/clientId),
    # or nil on any network / non-2xx / parse failure (logged). Preserves the block's
    # refreshToken when the server omits a rotated one, and its clientId (designOauth
    # carries its own; claudeAiOauth's is typically nil and dropped by .compact).
    def request_oauth_refresh(client_id:, refresh_token:, previous:, now_ms:)
      uri = URI(OAUTH_TOKEN_URL)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type:    "refresh_token",
        client_id:     client_id,
        refresh_token: refresh_token
      )
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[ClaudeCodeAdapter] Token refresh failed: #{response.code} #{response.body.to_s.truncate(200)}")
        return nil
      end
      data = JSON.parse(response.body)
      {
        "accessToken"  => data["access_token"],
        "refreshToken" => data["refresh_token"].presence || refresh_token, # rotation: keep old if server omits
        "expiresAt"    => now_ms + (data["expires_in"].to_i * 1000),
        "scopes"       => (data["scope"].present? ? data["scope"].split(" ") : previous["scopes"]),
        "clientId"     => previous["clientId"] # preserve (designOauth carries its own; claudeAiOauth may be nil → compacted)
      }.compact
    rescue StandardError => e
      Rails.logger.warn("[ClaudeCodeAdapter] Token refresh error: #{e.class}: #{e.message}")
      nil
    end

    # Keep whichever OAuth block has the later expiry; never drop one that only the
    # stored blob has (the incoming session may simply not have touched that scope).
    def freshest_oauth_block(current_block, incoming_block)
      return incoming_block if current_block.blank?
      return current_block if incoming_block.blank?

      incoming_block["expiresAt"].to_i >= current_block["expiresAt"].to_i ? incoming_block : current_block
    end

    # Returns an array of normalized models, or [] on any non-success / empty
    # result (the caller decides whether to fall back). Exactly one of api_key /
    # oauth_token should be provided.
    OAUTH_BETA_HEADER = "oauth-2025-04-20"

    def fetch_models_via_api(api_key: nil, oauth_token: nil)
      uri = URI(ANTHROPIC_MODELS_URL)
      uri.query = URI.encode_www_form(limit: 100)
      req = Net::HTTP::Get.new(uri)
      req["anthropic-version"] = "2023-06-01"

      if api_key.present?
        req["x-api-key"] = api_key
      elsif oauth_token.present?
        # OAuth tokens authenticate via Bearer + the oauth beta header (not x-api-key).
        req["authorization"] = "Bearer #{oauth_token}"
        req["anthropic-beta"] = OAUTH_BETA_HEADER
      else
        return []
      end

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      (data["data"] || []).filter_map do |m|
        next unless m["id"].to_s.include?("claude")

        { model_id: m["id"], display_name: m["display_name"] || m["id"], description: "#{m["max_input_tokens"]} max input tokens" }
      end
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

    # Permission mode is always bypassPermissions. Both interactive and
    # non_interactive sessions run headless in a sandbox container, so there is
    # nobody to answer a permission prompt. "auto" and "dontAsk" both still block
    # or deny tools that need a scope grant (e.g. DesignSync — "Permission to use
    # DesignSync has been denied because Claude Code is running in don't ask mode").
    # bypassPermissions never prompts/denies; the startup warning is pre-accepted
    # via skipDangerousModePermissionPrompt (see generate_settings).
    PERMISSION_DEFAULT_MODE = "bypassPermissions"

    def generate_settings(mcp_server_names = [], model: nil)
      settings = {
        "permissions" => {
          "defaultMode" => PERMISSION_DEFAULT_MODE,
          "allow" => allowed_tools(mcp_server_names),
          "deny" => [],
          "ask" => []
        },
        # Pre-accept the "Bypass Permissions mode" startup warning so a headless
        # container session never blocks on it. The operative key is
        # skipDangerousModePermissionPrompt — it is exactly what Claude Code writes
        # to settings.json when a user clicks through the warning once.
        # bypassPermissionsWarningAccepted alone does NOT suppress the prompt.
        "bypassPermissionsWarningAccepted" => true,
        "skipDangerousModePermissionPrompt" => true,
        "enableAllProjectMcpServers" => true,
        "env" => {
          "MCP_TIMEOUT" => Settings.agents.mcp.startup_timeout_ms.to_s
        }
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
