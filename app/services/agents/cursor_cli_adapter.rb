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

    # Cursor's accessToken is a JWT carrying an `exp` claim. Surface its expiry
    # (epoch ms) so AgentCredential#expires_at is populated and the proactive
    # refresh sweep selects the credential before expiry rather than only on 401.
    def token_expires_at(credentials)
      jwt_exp_ms(credentials["accessToken"])
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

    # Where `skills add -g -a cursor` puts a skill: the CLI installs into the
    # agent's own config directory, the same one holding cli-config.json.
    def skills_install_path
      "#{home_dir}/.cursor/skills"
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
          entry["args"] = mcp_stdio_args(s) if s.respond_to?(:args)
          entry["env"] = mcp_stdio_env(s)
        else
          entry["url"] = s.url if s.url.present?
          entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        end
        key = MCPServer.config_key_for(s.name)
        mcp_servers[key] = entry
        approvals << "#{key}-#{mcp_approval_hash(entry, workspace)}"
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
    # refresh_cursor_token! which persists under a row lock via persist_refreshed!.
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

    # Where #collect_usage records what it managed to do, on the session's
    # metadata. An empty Tokens/Cost cell means one of two very different things —
    # the agent genuinely spent nothing, or the meter broke — and without this they
    # are indistinguishable after the fact. Every exit path writes one status here:
    #
    #   recorded           usage was correlated and persisted
    #   no_mitm_log        no /var/log/mitm/http.log came back from the container
    #   no_rpc_windows     log present, but it holds no completed AgentService run
    #   no_access_token    the session's company has no cursor_cli credential
    #   api_error          the Dashboard API call failed (non-2xx or transport)
    #   no_api_events      the API answered, with nothing in the session's window
    #   no_matching_events events came back, none inside any RPC's in-flight span
    #   error              collection raised; the message is recorded alongside
    USAGE_DIAGNOSTIC_KEY = "usage_collection"

    # Collect and persist usage data at session cleanup.
    #
    # Flow:
    #   1. Parse MITM + http2-logger entries → RPC windows (request + response timestamps)
    #   2. One API call spanning [earliest request, latest response + tail]
    #   3. Match each API event to the RPC that was in flight when it was billed
    #   4. Persist matched events as UsageStatistic
    def collect_usage(terminal_session, artifacts = {})
      mitm_log = artifacts["logs/http.log"]

      if mitm_log.blank?
        Rails.logger.warn("[CursorCliAdapter] No MITM log collected for session #{terminal_session.id}")
        return record_usage_diagnostic(terminal_session, "no_mitm_log")
      end

      windows = build_rpc_windows(mitm_log)

      if windows.empty?
        Rails.logger.warn("[CursorCliAdapter] No completed AgentService runs in log for session #{terminal_session.id}")
        return record_usage_diagnostic(terminal_session, "no_rpc_windows", "log_lines" => mitm_log.lines.size)
      end

      # The credential, not just its token: the Dashboard API call has to be able
      # to refresh on a 401 the way every other Cursor call in this adapter does.
      credential = resolve_credential(terminal_session)
      if credential&.config_data&.dig("accessToken").blank?
        Rails.logger.warn("[CursorCliAdapter] No access token for session #{terminal_session.id}")
        return record_usage_diagnostic(terminal_session, "no_access_token", "windows_count" => windows.size)
      end

      # Single API call covering all windows. The end bound is the LATEST response
      # across every window — `windows` is sorted by request time, and with
      # overlapping RPCs the last one to start is not the last one to finish, so
      # taking its response would cut the final billing event out of the query.
      api_start = windows.first[:start_ms]
      api_end = windows.map { |w| w[:response_ms] }.max + RPC_WINDOW_AFTER_RESPONSE_MS
      time_window = { start_ms: api_start, end_ms: api_end }
      api_events = fetch_filtered_events(credential.config_data["accessToken"], time_window, credential: credential)

      # Store raw API result in metadata for debugging
      meta = terminal_session.metadata || {}
      meta["usage_api_result"] = {
        "fetched_at" => Time.current.iso8601,
        "time_window" => { "start_ms" => api_start, "end_ms" => api_end },
        "events" => api_events || [],
        "total_fetched" => api_events&.size || 0
      }
      terminal_session.update_column(:metadata, meta)

      if api_events.nil?
        Rails.logger.error("[CursorCliAdapter] Dashboard API call failed for session #{terminal_session.id}")
        return record_usage_diagnostic(terminal_session, "api_error", "windows_count" => windows.size)
      end

      if api_events.empty?
        Rails.logger.warn("[CursorCliAdapter] API returned 0 events for session #{terminal_session.id}")
        return record_usage_diagnostic(terminal_session, "no_api_events", "windows_count" => windows.size)
      end

      correlation = correlate_events(api_events, windows)
      persist_usage_statistic(terminal_session, correlation)
    rescue StandardError => e
      record_usage_diagnostic(terminal_session, "error", "message" => "#{e.class}: #{e.message}")
      raise
    end

    private

    # Stamp the outcome of a usage-collection attempt onto the session. Merges
    # into whatever metadata is already there (#collect_usage also stashes the raw
    # API result) and never raises — a failed diagnostic must not mask the real
    # failure it is describing.
    def record_usage_diagnostic(terminal_session, status, details = {})
      meta = terminal_session.metadata || {}
      meta[USAGE_DIAGNOSTIC_KEY] = details.transform_keys(&:to_s).merge(
        "status" => status.to_s,
        "collected_at" => Time.current.iso8601
      )
      terminal_session.update_column(:metadata, meta)
      nil
    rescue StandardError => e
      Rails.logger.warn("[CursorCliAdapter] Failed to record usage diagnostic: #{e.message}")
      nil
    end

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
      # Persist under a row lock with the rotation guard so a concurrent session
      # cleanup or sweep can't clobber a newer token.
      persisted = persist_refreshed!(credential, updated)
      Rails.logger.info("[CursorCliAdapter] Token refreshed for credential #{credential.id}")

      persisted["accessToken"]
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

    # The credential that paid for this session's usage: the one of the session's
    # company, never "the user's" — a multi-company user has one per company and the
    # dashboard call must read the account that was actually billed.
    def resolve_credential(terminal_session)
      SessionCompany.agent_credentials_for(terminal_session).find_by(agent_type: "cursor_cli")
    end

    # Cursor access tokens are short-lived JWTs (see #token_expires_at), and this
    # call happens at cleanup — by definition the far end of the session, when the
    # token stored at launch is most likely to have aged out. Refresh once on
    # 401/403 and retry, exactly as #fetch_available_models does; without it a
    # session longer than the token's lifetime silently recorded no usage at all.
    def fetch_filtered_events(access_token, time_window, credential: nil)
      response = request_filtered_events(access_token, time_window)

      if response && response_unauthorized?(response) && credential
        new_token = refresh_cursor_token!(credential)
        response = new_token ? request_filtered_events(new_token, time_window) : nil
      end

      return nil if response.nil?

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[CursorCliAdapter] API returned #{response.code}: #{response.body&.truncate(200)}")
        return nil
      end

      data = JSON.parse(response.body)
      data["usageEventsDisplay"] || []
    rescue StandardError => e
      Rails.logger.error("[CursorCliAdapter] API response parse error: #{e.class}: #{e.message}")
      nil
    end

    def request_filtered_events(access_token, time_window)
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

      http.request(request)
    rescue StandardError => e
      Rails.logger.error("[CursorCliAdapter] API request error: #{e.class}: #{e.message}")
      nil
    end

    # Tail added after an RPC's response, to absorb the lag between the response
    # and the moment Cursor stamps the billing event (empirically ~270ms ±100ms
    # past the response headers).
    RPC_WINDOW_AFTER_RESPONSE_MS = 1_000

    # =========================================================================
    # Correlation: RPC windows + Dashboard API events
    # =========================================================================

    # Correlate Dashboard API events with RPC time windows.
    # Each window is the RPC's in-flight span — see #match_windows_to_api.
    def correlate_events(api_events, windows)
      matched = match_windows_to_api(api_events, windows)

      windows.each_with_index do |w, i|
        Rails.logger.info(
          "[CursorCliAdapter] Window[#{i}]: req=#{format_ts(w[:start_ms])} " \
          "resp=#{format_ts(w[:response_ms])} rid=#{w[:request_id]}"
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

    # Match API events to RPC windows. A window is the RPC's whole in-flight span
    # plus the billing tail:
    #
    #     [request_ms, response_ms + RPC_WINDOW_AFTER_RESPONSE_MS]
    #
    # It used to start at `response_ms`, which silently assumed the response entry
    # was logged when the response HEADERS arrived — true of http2-logger and
    # node-http-logger, both of which fire on the `response` event. It is NOT true
    # of mitmproxy: mitm_logger.py streams the body and writes its entry when the
    # stream ENDS, which for an agent turn is minutes later. Since `useHttp1ForAgent`
    # routes AgentService/RunSSE through the proxy, a session whose only response
    # entries came from mitmproxy had every billing event fall before its window and
    # recorded no usage at all. Anchoring on the request makes the window correct for
    # both loggers, because the billing event cannot predate the request that caused it.
    #
    # The trade-off: while one RPC is in flight, an event billed to a CONCURRENT
    # session on the same Cursor account can land inside this session's window. The
    # API query already spans the whole session, so the two were never separable
    # here; attributing such an event to the wrong one of two concurrent sessions
    # beats dropping the usage of both.
    def match_windows_to_api(api_events, windows)
      matched = Set.new

      windows.each do |w|
        lo = w[:start_ms]
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
      details = correlation[:details]

      if events.empty?
        Rails.logger.warn(
          "[CursorCliAdapter] No usage events matched for session #{terminal_session.id} " \
          "(windows=#{details[:windows_count]} api=#{details[:api_count]})"
        )
        return record_usage_diagnostic(
          terminal_session, "no_matching_events",
          "windows_count" => details[:windows_count], "api_count" => details[:api_count]
        )
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

      Rails.logger.info(
        "[CursorCliAdapter] Session #{terminal_session.id} usage: " \
        "#{events.size} events (source=#{correlation[:source]}), " \
        "in=#{totals[:input_tokens]} out=#{totals[:output_tokens]} " \
        "cache_r=#{totals[:cache_read_tokens]} cache_w=#{totals[:cache_write_tokens]} " \
        "cost=$#{'%.2f' % (totals[:total_cents] / 100.0)}" \
        "#{details[:unmatched_api] ? " unmatched_api=#{details[:unmatched_api]}" : ''}"
      )

      record_usage_diagnostic(
        terminal_session, "recorded",
        "windows_count" => details[:windows_count], "api_count" => details[:api_count],
        "matched_count" => details[:matched_count]
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
