# frozen_string_literal: true

require "net/http"
require "json"
require "set"

module Agents
  # Cursor CLI adapter for credential handling
  # Config files:
  #   - ~/.config/cursor/auth.json (tokens, Linux XDG path — primary)
  #   - ~/.cursor/auth.json (tokens, alternative path — newer CLI builds)
  #   - ~/.cursor/cli-config.json (settings)
  # Auth: OAuth via Cursor (agent login)
  class CursorCliAdapter < BaseAdapter
    def self.default_config_paths
      [ "~/.cursor/cli-config.json", ".cursorrules" ]
    end

    def config_path
      # Primary auth file (XDG: $XDG_CONFIG_HOME/cursor/auth.json)
      "#{home_dir}/.config/cursor/auth.json"
    end

    # Alternative auth path used by newer Cursor CLI builds
    def config_path_alt
      "#{home_dir}/.cursor/auth.json"
    end

    def home_dir
      "/home/cursor"
    end

    # Comma-separated — watcher checks both paths, accepts whichever has the token
    def auth_watch_path
      "#{config_path},#{config_path_alt}"
    end

    # Both candidate paths for extraction at session cleanup
    def auth_file_paths
      [ config_path, config_path_alt ]
    end

    # Keys that indicate auth is complete
    def auth_required_keys
      %w[accessToken]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      config["accessToken"].present?
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice("accessToken", "refreshToken").compact
    end

    # Generate auth.json for a new container
    def generate_config(credentials, workflow_config = {})
      {
        "accessToken" => credentials["accessToken"],
        "refreshToken" => credentials["refreshToken"]
      }.compact
    end

    # Override to write multiple config files
    def config_files(credentials, workflow_config = {})
      workspace = workflow_config[:workspace] || "/workspace"
      auth_json = generate_config(credentials, workflow_config).to_json
      {
        # Auth tokens — write to both paths so any CLI version picks them up
        config_path => auth_json,
        config_path_alt => auth_json,
        # CLI settings with full permissions
        "#{home_dir}/.cursor/cli-config.json" => generate_cli_config(workflow_config).to_json,
        # Workspace trust (skip trust dialog)
        "#{home_dir}/.cursor/projects#{workspace}/.workspace-trusted" => generate_workspace_trust(workspace).to_json
      }
    end

    # Session command: agent --force (interactive), agent --force -p (non-interactive)
    # --force: auto-approve all tools unless explicitly denied (yolo mode)
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file
    def session_command(mode:, prompt: nil, model: nil)
      model ? "agent --force --model #{Shellwords.shellescape(model)}" : "agent --force"
    end

    # Context file: /workspace/AGENTS.md (auto-read by Cursor at startup, no git required)
    def context_file_path
      "/workspace/AGENTS.md"
    end

    def skills_agent_name
      "cursor"
    end

    # MCP config: /workspace/.cursor/mcp.json + pre-approved mcp-approvals.json
    def mcp_config(servers)
      workspace = "/workspace"
      mcp_servers = {}
      approvals = []

      servers.each do |s|
        entry = {}
        if s.transport.to_s == "stdio"
          entry["command"] = s.command if s.respond_to?(:command)
          entry["args"] = s.args if s.respond_to?(:args)
          entry["env"] = s.env if s.respond_to?(:env) && s.env.present?
        else
          entry["url"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        mcp_servers[s.name] = entry
        approvals << "#{s.name}-#{mcp_approval_hash(entry, workspace)}"
      end

      {
        "#{workspace}/.cursor/mcp.json" => { "mcpServers" => mcp_servers }.to_json,
        "#{home_dir}/.cursor/projects#{workspace}/mcp-approvals.json" => approvals.to_json
      }
    end

    # Fetch available models from Cursor API (Connect protocol, JSON format).
    CURSOR_MODELS_URL = "https://api2.cursor.sh/aiserver.v1.AiService/GetUsableModels"
    CURSOR_AUTH_URL = "https://authenticator.cursor.sh/oauth/token"
    CURSOR_CLIENT_ID = "cursor-cli"

    def fetch_available_models(credentials, credential: nil)
      access_token = credentials["accessToken"]
      return [] if access_token.blank?

      response = request_models(access_token)

      if response_unauthorized?(response) && credential
        new_token = refresh_cursor_token!(credential)
        return [] unless new_token

        response = request_models(new_token)
      end

      return [] unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      return [] if data["code"].present?

      parse_models_json(data)
    rescue StandardError => e
      Rails.logger.warn("[CursorCliAdapter] fetch_available_models failed: #{e.message}")
      []
    end

    # Proactive-refresh hook (Temporal sweep). Thin wrapper over the reactive
    # refresh_cursor_token! which already persists via credential.update!.
    # @param credential [AgentCredential]
    # @return [Hash] { status: :refreshed | :error, detail: String | nil }
    def refresh!(credential)
      new_token = refresh_cursor_token!(credential)
      new_token ? { status: :refreshed, detail: nil }
                : { status: :error, detail: "cursor token refresh failed" }
    end

    # Env vars for MITM proxy and http2-logger configuration.
    # MITM_TRACKED_DOMAINS limits mitm_logger.py to cursor.sh traffic only.
    # http2-logger.js uses MITM_LOG_PATH to write AgentService/Run timestamps.
    def default_env_vars(_session)
      {
        "MITM_LOG_PATH" => "/var/log/mitm/http.log",
        "MITM_TRACKED_DOMAINS" => "cursor.sh"
      }
    end

    # Log files to collect from container after session ends
    def session_log_paths
      super + %w[/var/log/mitm/http.log]
    end

    # Collect and persist usage data at session cleanup.
    #
    # Flow:
    #   1. Parse http2-logger entries from MITM log → RPC windows (request + response timestamps)
    #   2. One API call: [earliest_request, latest_response + 500ms]
    #   3. Match each API event to its RPC window [response_ts, response_ts + 500ms]
    #   4. Persist matched events as UsageStatistic
    def collect_usage(terminal_session, artifacts = {})
      mitm_log = artifacts["logs/http.log"]
      windows = build_rpc_windows(mitm_log)

      if windows.empty?
        Rails.logger.warn("[CursorCliAdapter] No completed AgentService runs in log for session #{terminal_session.id}")
        return
      end

      access_token = resolve_access_token(terminal_session)
      unless access_token
        Rails.logger.warn("[CursorCliAdapter] No access token for session #{terminal_session.id}")
        return
      end

      # Single API call covering all windows.
      api_start = windows.first[:start_ms]
      api_end = windows.last[:response_ms] + RPC_WINDOW_AFTER_RESPONSE_MS
      api_events = fetch_filtered_events(access_token, { start_ms: api_start, end_ms: api_end })

      # Store raw API result in metadata for debugging
      meta = terminal_session.metadata || {}
      meta["usage_api_result"] = {
        "fetched_at" => Time.current.iso8601,
        "time_window" => { "start_ms" => api_start, "end_ms" => api_end },
        "events" => api_events || [],
        "total_fetched" => api_events&.size || 0
      }
      terminal_session.update_column(:metadata, meta)

      if api_events.blank?
        Rails.logger.warn("[CursorCliAdapter] API returned 0 events for session #{terminal_session.id}")
        return
      end

      correlation = correlate_events(api_events, windows)
      persist_usage_statistic(terminal_session, correlation)
    end

    private

    def request_models(access_token)
      uri = URI(CURSOR_MODELS_URL)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      req["Content-Type"] = "application/json"
      req["Connect-Protocol-Version"] = "1"
      req.body = "{}"
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
    end

    def response_unauthorized?(response)
      response.code == "401" || response.code == "403"
    end

    def refresh_cursor_token!(credential)
      refresh_token = credential.config_data["refreshToken"]
      return nil if refresh_token.blank?

      uri = URI(CURSOR_AUTH_URL)
      body = URI.encode_www_form(
        grant_type: "refresh_token",
        client_id: CURSOR_CLIENT_ID,
        refresh_token: refresh_token
      )
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = body

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(req) }

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[CursorCliAdapter] Token refresh failed: #{response.code} #{response.body.to_s.truncate(200)}")
        return nil
      end

      data = JSON.parse(response.body)
      new_access = data["access_token"]
      return nil if new_access.blank?

      updated = credential.config_data.merge(
        "accessToken" => new_access,
        "refreshToken" => data["refresh_token"] || refresh_token
      )
      credential.update!(config_data: updated)
      Rails.logger.info("[CursorCliAdapter] Token refreshed for credential #{credential.id}")

      new_access
    rescue StandardError => e
      Rails.logger.warn("[CursorCliAdapter] Token refresh error: #{e.message}")
      nil
    end

    CURSOR_API_BASE = "https://api2.cursor.sh"
    FILTERED_USAGE_ENDPOINT = "/aiserver.v1.DashboardService/GetFilteredUsageEvents"
    API_PAGE_SIZE = 200

    # =========================================================================
    # Cursor Dashboard API
    # =========================================================================

    def resolve_access_token(terminal_session)
      credential = terminal_session.user
                                   .agent_credentials
                                   .find_by(agent_type: "cursor_cli")
      credential&.config_data&.dig("accessToken")
    end

    def fetch_filtered_events(access_token, time_window)
      uri = URI("#{CURSOR_API_BASE}#{FILTERED_USAGE_ENDPOINT}")

      body = {
        startDate: time_window[:start_ms].to_s,
        endDate: time_window[:end_ms].to_s,
        page: 1,
        pageSize: API_PAGE_SIZE
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request["Authorization"] = "Bearer #{access_token}"
      request["Content-Type"] = "application/json"
      request["Connect-Protocol-Version"] = "1"
      request.body = body.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[CursorCliAdapter] API returned #{response.code}: #{response.body&.truncate(200)}")
        return nil
      end

      data = JSON.parse(response.body)
      data["usageEventsDisplay"] || []
    rescue StandardError => e
      Rails.logger.error("[CursorCliAdapter] API request error: #{e.class}: #{e.message}")
      nil
    end

    # Billing timestamp ≈ response_headers_ts + 270ms (empirically ±100ms).
    # Use 1s window after response for reliable matching.
    RPC_WINDOW_AFTER_RESPONSE_MS = 1_000

    # =========================================================================
    # Correlation: RPC windows + Dashboard API events
    # =========================================================================

    # Correlate Dashboard API events with RPC time windows.
    # Each window is [response_ts, response_ts + 500ms].
    def correlate_events(api_events, windows)
      matched = match_windows_to_api(api_events, windows)

      windows.each_with_index do |w, i|
        Rails.logger.info(
          "[CursorCliAdapter] Window[#{i}]: resp=#{format_ts(w[:response_ms])} " \
          "rid=#{w[:request_id]}"
        )
      end
      Rails.logger.info(
        "[CursorCliAdapter] Correlation: windows=#{windows.size} " \
        "api=#{api_events.size} → matched=#{matched.size}"
      )

      { matched_events: matched, source: "cursor_api",
        details: { windows_count: windows.size, api_count: api_events.size,
                   matched_count: matched.size } }
    end

    AGENT_SERVICE_RUN_PATH = "/agent.v1.AgentService/Run"
    AGENT_SERVICE_RUN_SSE_PATH = "/agent.v1.AgentService/RunSSE"

    # Build correlation windows from MITM + http2-logger entries.
    #
    # HTTP/2 Run (legacy): http2-logger pairs request/response by x-request-id.
    # HTTP/1 RunSSE (useHttp1ForAgent): mitmproxy logs requests with x-request-id but
    # streaming responses often omit it — pair those by FIFO order per path.
    def build_rpc_windows(log_content)
      requests = {}        # request_id → { start_ms:, request_id:, path: }
      responses = {}       # request_id → response_ms
      pending_by_path = {} # path → [request_id] awaiting a response

      (log_content || "").each_line do |line|
        entry = JSON.parse(line.strip)
        next unless agent_service_run_path?(entry["path"])

        path = entry["path"]
        ts = parse_iso_to_epoch_ms(entry["ts"])
        next unless ts
        source = entry["_source"]
        rid = extract_request_id(entry)

        case entry["direction"]
        when "request"
          next if source == "node-http-logger"
          next if rid.blank?

          requests[rid] = { start_ms: ts, request_id: rid, path: path }
          (pending_by_path[path] ||= []) << rid
        when "response"
          if source == "node-http-logger"
            assign_response_timestamp!(responses, pending_by_path, path, ts)
            next
          end

          if rid.present?
            responses[rid] = ts unless responses.key?(rid)
            pending_by_path[path]&.delete(rid)
          else
            assign_response_timestamp!(responses, pending_by_path, path, ts)
          end
        end
      rescue JSON::ParserError
        next
      end

      requests.values.filter_map do |w|
        response_ms = responses[w[:request_id]]
        next unless response_ms

        w.merge(response_ms: response_ms)
      end.sort_by { |w| w[:start_ms] }
    end

    def assign_response_timestamp!(responses, pending_by_path, path, ts)
      pending_rid = pending_by_path.dig(path)&.first
      return if pending_rid.blank?
      return if responses.key?(pending_rid)

      responses[pending_rid] = ts
      pending_by_path[path].shift
    end

    def agent_service_run_path?(path)
      path == AGENT_SERVICE_RUN_PATH || path == AGENT_SERVICE_RUN_SSE_PATH
    end

    def extract_request_id(entry)
      headers = entry["headers"] || {}
      headers["x-request-id"].presence || headers["X-Request-Id"].presence
    end

    # Match API events to RPC windows: [response_ms, response_ms + 500ms].
    # Billing ≈ response_ts + 270ms (empirically +190–310ms).
    def match_windows_to_api(api_events, windows)
      matched = Set.new

      windows.each do |w|
        lo = w[:response_ms]
        hi = w[:response_ms] + RPC_WINDOW_AFTER_RESPONSE_MS

        api_events.each_with_index do |event, idx|
          next if matched.include?(idx)
          matched.add(idx) if event["timestamp"].to_i.between?(lo, hi)
        end
      end

      matched.map { |idx| api_events[idx] }
    end

    # Parse ISO 8601 timestamp to epoch milliseconds.
    def parse_iso_to_epoch_ms(iso_string)
      return nil if iso_string.blank?

      (Time.parse(iso_string).to_f * 1000).to_i
    rescue ArgumentError
      nil
    end

    # Format epoch_ms as HH:MM:SS.mmm for readable logs.
    def format_ts(epoch_ms)
      Time.at(epoch_ms / 1000.0).utc.strftime("%H:%M:%S.%3N")
    end

    # =========================================================================
    # Usage Persistence (at cleanup)
    # =========================================================================

    def persist_usage_statistic(terminal_session, correlation)
      events = correlation[:matched_events]

      if events.empty?
        Rails.logger.info("[CursorCliAdapter] No usage events for session #{terminal_session.id}")
        return
      end

      totals = aggregate_events(events)
      models = events.map { |e| e["model"] }.compact.uniq

      stat = terminal_session.usage_statistic || terminal_session.build_usage_statistic
      stat.assign_attributes(
        input_tokens: totals[:input_tokens],
        output_tokens: totals[:output_tokens],
        cache_write_tokens: totals[:cache_write_tokens],
        cache_read_tokens: totals[:cache_read_tokens],
        total_cents_precise: totals[:total_cents],
        cost_cents: totals[:total_cents].ceil,
        models: models,
        source: correlation[:source],
        events_count: events.size,
        events_data: events
      )
      stat.save!

      details = correlation[:details]
      Rails.logger.info(
        "[CursorCliAdapter] Session #{terminal_session.id} usage: " \
        "#{events.size} events (source=#{correlation[:source]}), " \
        "in=#{totals[:input_tokens]} out=#{totals[:output_tokens]} " \
        "cache_r=#{totals[:cache_read_tokens]} cache_w=#{totals[:cache_write_tokens]} " \
        "cost=$#{'%.2f' % (totals[:total_cents] / 100.0)}" \
        "#{details[:unmatched_api] ? " unmatched_api=#{details[:unmatched_api]}" : ''}"
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
    # OTLP payload helpers
    # =========================================================================

    def generate_cli_config(workflow_config)
      {
        # Required fields per docs
        "version" => 1,
        "editor" => {
          "vimMode" => false
        },
        "permissions" => {
          # Allow common dev commands
          "allow" => [
            "Shell(ls)", "Shell(cat)", "Shell(head)", "Shell(tail)", "Shell(grep)", "Shell(find)",
            "Shell(git)", "Shell(npm)", "Shell(yarn)", "Shell(pnpm)", "Shell(node)",
            "Shell(python)", "Shell(pip)", "Shell(python3)", "Shell(pip3)",
            "Shell(ruby)", "Shell(bundle)", "Shell(rails)", "Shell(rake)",
            "Shell(make)", "Shell(cargo)", "Shell(go)",
            "Shell(curl)", "Shell(wget)",
            "Shell(mkdir)", "Shell(cp)", "Shell(mv)", "Shell(touch)",
            "Shell(echo)", "Shell(pwd)", "Shell(cd)", "Shell(tree)",
            "Read(**/*)",    # Allow reading all files
            "Write(**/*)",  # Allow writing all files
            "Mcp(*:*)",    # Allow all MCP server tools without confirmation
            "WebFetch(**)"  # Allow fetching any URL (** matches domains and paths)
          ],
          # Deny dangerous commands
          "deny" => [
            "Shell(rm)",    # Prevent destructive removal
            "Shell(sudo)",  # No privilege escalation
            "Read(.env*)",  # Protect env files from reading
            "Write(.env*)"  # Protect env files from writing
          ]
        },
        # Optional fields
        "hasChangedDefaultModel" => false,
        "network" => {
          # HTTP/2 AgentService/Run to api5 bypasses MITM proxy and hangs in interactive mode.
          # HTTP/1 routes through HTTPS_PROXY so mitmproxy + usage logging work.
          "useHttp1ForAgent" => true
        },
        "attribution" => {
          "attributeCommitsToAgent" => true,
          "attributePRsToAgent" => true
        }
      }
    end

    def generate_workspace_trust(workspace)
      {
        "trustedAt" => Time.current.iso8601(3),
        "workspacePath" => workspace
      }
    end

    # Parse models from Connect JSON response.
    # Response structure: { "models": [{ "modelId": "...", "displayName": "...", ... }] }
    # or nested under different keys depending on API version.
    def parse_models_json(data)
      models_raw = data["models"] || data["usableModels"] || []

      models_raw.filter_map do |m|
        model_id = m["modelId"] || m["model_id"] || m["id"]
        next if model_id.blank?

        display_name = m["displayName"] || m["display_name"] || m["name"] || model_id
        description = (m["description"] || "").to_s.truncate(120)

        { model_id: model_id, display_name: display_name, description: description }
      end.uniq { |m| m[:model_id] }
    end

    # Generate MCP approval hash matching Cursor CLI algorithm:
    # sha256(JSON.stringify({path: workspace, server: serverConfig})).substring(0, 16)
    def mcp_approval_hash(server_entry, workspace)
      payload = { "path" => workspace, "server" => server_entry }
      Digest::SHA256.hexdigest(payload.to_json)[0, 16]
    end
  end
end
