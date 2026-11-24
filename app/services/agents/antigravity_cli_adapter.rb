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
    ONBOARDING_PATH = ".gemini/antigravity-cli/cache/onboarding.json"
    CONSUMER_ONBOARDING = { "consumerOnboardingComplete" => true, "enterpriseOnboardingComplete" => false,
                            "onboardingComplete" => true }.freeze
    WORKSPACE = "/workspace"

    # The metadata key under which the last `/usage` probe's snapshot is stored,
    # and the print-mode command that reads it. `/usage` is the CLI's own quota
    # view; in print mode it answers with `num_turns: 0` and a zeroed `usage`
    # (verified against agy 1.5.9), so the probe spends no model turn. Never add
    # `--disable-slash-commands`: agy then sends `/usage` as a billed prompt.
    SUBSCRIPTION_USAGE_KEY = "subscription_usage"
    USAGE_PROBE_COMMAND = [ "agy", "-p", "/usage", "--output-format", "json", "--print-timeout", "20s" ].freeze

    # API-equivalent prices in USD per million tokens. Keep this table beside the
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
      "gpt-oss-120b-medium" => { input: 0.15, output: 0.60, cache_read: 0.015 },
      # Google's standard rate from 2026-12-01; through 2026-11-30 it bills half of this.
      "gemini-4-argon-high" => { input: 4.00, output: 20.00, cache_read: 0.20 },
      "gemini-4-argon-medium" => { input: 4.00, output: 20.00, cache_read: 0.20 },
      "gemini-4-argon-low" => { input: 4.00, output: 20.00, cache_read: 0.20 },
      "claude-opus-5-5-max" => { input: 4.00, output: 20.00, cache_read: 0.20 },
      "claude-opus-5-5-high" => { input: 4.00, output: 20.00, cache_read: 0.20 },
      "claude-opus-5-5-medium" => { input: 4.00, output: 20.00, cache_read: 0.20 },
      "claude-opus-5-5-low" => { input: 4.00, output: 20.00, cache_read: 0.20 },
      "claude-sonnet-5-5-max" => { input: 2.00, output: 10.00, cache_read: 0.20 },
      "claude-sonnet-5-5-high" => { input: 2.00, output: 10.00, cache_read: 0.20 },
      "claude-sonnet-5-5-medium" => { input: 2.00, output: 10.00, cache_read: 0.20 },
      "claude-sonnet-5-5-low" => { input: 2.00, output: 10.00, cache_read: 0.20 }
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
    def perform_refresh!(credential, margin_ms: nil)
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

    # agy renews its Google token inside the container; that is all it may report.
    def rotatable_credential_keys = %w[access_token refresh_token token_type expiry]

    def writeback_file_paths = [ config_path ]
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

    # Every session container is a fresh install, so agy would run its first-run
    # onboarding — colour scheme, then "Terms of Service & Data Use" with the telemetry
    # box pre-ticked — at the start of every interactive session. The user went through
    # it once when signing in (the auth container is not seeded with this), and this is
    # the file agy itself leaves behind after it. Consumer logins only: the "Google Cloud
    # project" login has its own enterprise terms, never observed here.
    def config_files(credentials, workflow_config = {})
      files = {
        "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json,
        config_path => generate_config(credentials).to_json
      }
      files["#{home_dir}/#{ONBOARDING_PATH}"] = CONSUMER_ONBOARDING.to_json if credentials["auth_method"] == "consumer"
      files["#{home_dir}/#{HOOKS_PATH}"] = telemetry_hooks.to_json if workflow_config[:full_telemetry]
      files
    end

    # agy exports no telemetry of its own to anyone but Google; for a session with full
    # telemetry (TerminalSession#full_telemetry?) its hooks report the prompt, the model's
    # output per invocation, each tool call with its arguments and error, and the turn's
    # end. Not a tool's result or tokens (1.5.0). A tool hook takes a matcher and its
    # handlers; the others take handlers directly. A failing PreToolUse handler denies the
    # tool, as does any stdout but none.
    HOOKS_PATH = ".gemini/config/hooks.json"
    HOOK_EVENTS = %w[SessionStart PreInvocation PostInvocation PreToolUse PostToolUse Stop].freeze
    TOOL_HOOK_EVENTS = %w[PreToolUse PostToolUse].freeze

    def telemetry_hooks
      events = HOOK_EVENTS.to_h do |event|
        handler = { "type" => "command", "command" => otlp_hook_command("antigravity-cli", event), "timeout" => 10 }
        [ event, TOOL_HOOK_EVENTS.include?(event) ? [ { "matcher" => "*", "hooks" => [ handler ] } ] : [ handler ] ]
      end
      { "aixle-telemetry" => events }
    end

    # Written before auth starts so the auth terminal already has tips disabled and
    # the workspace trusted when `agy` itself launches (see AgentAuthStrategy#before_exec).
    def auth_setup_files
      { "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json }
    end

    # `agy` is a Go binary, so it honours HTTP(S)_PROXY and its traffic goes through the
    # container's MITM proxy. Google's token endpoint is the one that matters — that a
    # refresh happened, against which endpoint, with what status — and the Cloud Code
    # service shows the model calls and the quota answers. Not `googleapis.com` whole:
    # that is also every GCS download and Google Cloud call the agent makes.
    MITM_DOMAINS = %w[oauth2.googleapis.com cloudcode-pa.googleapis.com daily-cloudcode-pa.googleapis.com].freeze

    def default_env_vars(session, callbacks:)
      {
        "AGY_CLI_HIDE_LOGO" => "1",
        # Without it the CLI, run as root, replaces the pinned /usr/local/bin/agy with the
        # vendor's newest release a second after launch (1.1.27 installed 1.4.2), so a
        # session runs whatever shipped that day instead of the pin. Only the exact value
        # "true" is honoured: "1", "TRUE" and "yes" still update.
        "AGY_CLI_DISABLE_AUTO_UPDATE" => "true",
        **otlp_hook_env(session, callbacks[:otel])
      }
    end

    def mitm_tracked_domains
      MITM_DOMAINS.dup
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
        next unless model.is_a?(Hash) && model["disabled"] != true

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

    # Resume, measured 2026-11-20: the conversation database, its brain directory and
    # the map from workspace to conversation.
    def conversation_paths
      %w[.gemini/antigravity-cli/conversations .gemini/antigravity-cli/brain
         .gemini/antigravity-cli/cache/last_conversations.json]
    end
    def conversation_id_command
      "grep -oE '\"/workspace\": *\"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' .gemini/antigravity-cli/cache/last_conversations.json 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'"
    end
    def resume_arguments(id) = "--conversation=#{id}"

    # Automatic sessions run in the TUI like interactive ones, with the step's prompt submitted
    # by `-i` (#prompt_argument). No `--effort`: agy's model ids carry the effort
    # (`gemini-3.8-flash-high`), and `--effort` only applies to a model group, which the
    # model list never offers. In the TUI an unknown model, or `--effort` on a model id, does
    # not stop agy: it runs the account's default model and says so only in its own log
    # (1.5.13), which is why the model is checked before launch (#runs_default_model_for_unknown?).
    def session_command(mode:, model: nil, effort: nil)
      parts = [ "agy" ]
      parts += [ "--model", Shellwords.shellescape(model) ] if model.present?
      parts << "--dangerously-skip-permissions"
      parts.join(" ")
    end

    def prompt_argument(prompt) = "-i #{prompt}"

    def runs_default_model_for_unknown? = true

    # agy keeps one transcript per conversation, named after the conversation id, in print
    # mode and in the TUI alike. Every model call is a PLANNER_RESPONSE line with that call's
    # tokens: input without cache reads, output with thinking (1.5.13, checked against
    # print mode's own `result` totals).
    TRANSCRIPT_GLOB = "/home/antigravity/.gemini/antigravity-cli/brain/*/.system_generated/logs/transcript.jsonl"
    TRANSCRIPT_PATH = %r{\A/home/antigravity/\.gemini/antigravity-cli/brain/([^/]+)/\.system_generated/logs/transcript\.jsonl\z}
    TRANSCRIPT_SUFFIX = ".transcript.jsonl"

    def session_log_paths
      super + [ "/var/log/mitm/http.log", TRANSCRIPT_GLOB ]
    end

    # brain/<conversation id>/.system_generated/logs/transcript.jsonl → <id>.transcript.jsonl
    def session_log_name(path)
      match = TRANSCRIPT_PATH.match(path)
      match ? "#{match[1]}#{TRANSCRIPT_SUFFIX}" : super
    end

    def collect_usage(terminal_session, artifacts = {})
      # Accumulator.record always increments, so a cleanup retry (max_attempts: 2) re-reading
      # the same transcripts would double every value already persisted.
      return if terminal_session.usage_statistic.present?

      transcripts = artifacts.select { |name, _| name.to_s.end_with?(TRANSCRIPT_SUFFIX) }.values
      events = usage_events(transcripts, terminal_session)
      return if events.empty?

      UsageStatistics::Accumulator.record(terminal_session: terminal_session, events: events,
                                          source: "antigravity_transcript")
    end

    # Antigravity's remaining quota is read from the CLI itself (`agy`'s `/usage`
    # print mode), which only runs inside the container — so the reading is a
    # snapshot captured here at cleanup, not a live server-side fetch. Only the
    # session phase is probed: at :auth the credential was just captured and no
    # quota has been spent since the last session.
    def collect_credential_metadata(runtime, container, credential, phase)
      return {} if phase != :session || credential.blank?

      stdout, _stderr, status = runtime.exec(container, USAGE_PROBE_COMMAND, stdout: true, stderr: true)
      return {} unless status.to_i.zero?

      windows = usage_windows_from_probe(Array(stdout).join)
      return {} if windows.empty?

      { SUBSCRIPTION_USAGE_KEY => { "fetched_at" => Time.current.utc.iso8601, "windows" => windows } }
    rescue StandardError => e
      Rails.logger.warn("[AntigravityCliAdapter] could not read the quota: #{e.class}: #{e.message}")
      {}
    end

    # The quota snapshot is the only source for this runtime's remaining quota,
    # and workflow steps are where Antigravity runs — so its cleanup must probe
    # even though every other runtime skips metadata collection there.
    def collect_credential_metadata_on_workflow_step?
      true
    end

    # Reads the snapshot #collect_credential_metadata stored. Lives outside
    # #fetch_subscription_usage because the server cannot fetch this quota live;
    # SubscriptionUsageService prefers it when the adapter responds to it.
    def fetch_subscription_usage_from_snapshot(credential)
      snapshot = credential&.metadata&.dig(SUBSCRIPTION_USAGE_KEY)
      return nil unless snapshot.is_a?(Hash)

      windows = Array(snapshot["windows"]).map(&:symbolize_keys)
      # A window that reset since the snapshot was taken is stale: the card has
      # no "last updated" line, so a week-old 95% reading would still say "resets
      # now" after the quota already reset. Drop reset windows; a snapshot with
      # none left is no reading at all.
      windows = windows.reject { |window| window_reset?(window[:resets_at]) }
      return nil if windows.empty?

      { status: "ok", windows: windows, fetched_at: snapshot["fetched_at"] }
    end

    def window_reset?(resets_at)
      return false if resets_at.blank?

      Time.zone.parse(resets_at.to_s) < Time.current
    rescue ArgumentError
      false
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

    # The `/usage` print-mode envelope is a single JSON line; the CLI may
    # interleave other output around it. Each bucket becomes one window.
    def usage_windows_from_probe(stdout)
      envelope = parse_print_envelope(stdout)
      return [] unless envelope.is_a?(Hash) && envelope["status"] == "SUCCESS"

      command = envelope["command"]
      data = command.is_a?(Hash) ? command["data"] : nil
      groups = data.is_a?(Hash) ? Array(data["groups"]) : []
      groups.flat_map { |group| usage_windows_from_group(group) }.compact
    end

    def usage_windows_from_group(group)
      return [] unless group.is_a?(Hash)

      group_name = group["name"].to_s.presence
      buckets = Array(group["buckets"]).select { |bucket| bucket.is_a?(Hash) && bucket["disabled"] != true }
      return [] if buckets.empty?

      buckets.filter_map do |bucket|
        fraction = bucket["remaining_fraction"]
        key = bucket["id"].to_s.presence
        next if fraction.nil? || key.blank?

        bucket_name = bucket["name"].to_s.presence
        # The bucket id is a dynamic vendor slug (e.g. "gemini-weekly"), so the
        # card can't label it statically. Carry a human label: the group name,
        # qualified by the bucket name only when a group has several buckets.
        label = buckets.one? || bucket_name.blank? ? group_name : [ group_name, bucket_name ].compact.join(" · ")

        {
          key: key,
          label: label.presence,
          utilization: ((1.0 - fraction.to_f) * 100).clamp(0.0, 100.0),
          resets_at: bucket["reset_time"].presence,
          window_duration_mins: window_minutes_for(bucket["window"])
        }.compact
      end
    end

    def window_minutes_for(window)
      { "weekly" => 10_080, "5h" => 300 }[window.to_s]
    end

    def parse_print_envelope(stdout)
      stdout.to_s.each_line do |line|
        trimmed = line.strip
        next unless trimmed.start_with?("{")

        parsed = JSON.parse(trimmed)
        return parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
      nil
    end

    def usage_events(transcripts, terminal_session)
      totals = Hash.new { |hash, model| hash[model] = { input: 0, output: 0, cached: 0 } }
      transcripts.each do |transcript|
        transcript.each_line do |line|
          call = parse_json(line)
          next unless call.is_a?(Hash) && call["type"] == "PLANNER_RESPONSE"

          sums = totals[call["model"].presence || terminal_session.requested_model.presence || default_model_for(terminal_session)]
          sums[:input] += call["input_tokens"].to_i
          sums[:output] += call["output_tokens"].to_i
          sums[:cached] += call["cache_read_tokens"].to_i
        end
      end

      totals.filter_map do |model, sums|
        next if sums.values.all?(&:zero?)

        {
          "model" => model,
          "timestamp" => terminal_session.finished_at&.to_i&.to_s,
          "tokenUsage" => {
            "inputTokens" => sums[:input],
            "outputTokens" => sums[:output],
            "cacheReadTokens" => sums[:cached],
            "cacheWriteTokens" => 0,
            "totalCents" => usage_cost_cents(model, sums[:input], sums[:output], sums[:cached])
          },
          "source" => "antigravity_transcript"
        }
      end
    end

    def default_model_for(terminal_session)
      SessionCompany.agent_credentials_for(terminal_session)
                    .find_by(agent_type: "antigravity_cli")&.default_model
    end

    # Input excludes cache reads, so each bucket is priced on its own.
    def usage_cost_cents(model, input_tokens, output_tokens, cache_read_tokens)
      pricing = MODEL_PRICING[model]
      unless pricing
        Rails.logger.warn("[AntigravityCliAdapter] no configured pricing for model #{model.inspect}")
        return 0.0
      end

      ((input_tokens * pricing[:input]) + (cache_read_tokens * pricing[:cache_read]) +
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
      # No telemetry key: since 1.1.28 telemetry follows the Google account's own
      # setting, and agy drops `enableTelemetry` from this file when it rewrites it.
      # The trusted workspace answers "Do you trust the contents of this project?".
      # `altScreenMode: never` keeps the TUI off the alternate screen (its default in
      # 1.5.0), where the tmux scrollback, the live log tail and the stored log replay
      # would hold a single frame with nothing to scroll back to.
      { "showTips" => false, "trustedWorkspaces" => [ WORKSPACE ], "altScreenMode" => "never" }
    end
  end
end
