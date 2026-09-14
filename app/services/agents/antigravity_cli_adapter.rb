# frozen_string_literal: true

require "shellwords"
require "stringio"
require "zlib"

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

    MODELS_URL = "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
    CONSUMER_PROJECT = "aicode-consumers"

    # Used only when the live catalogue is unavailable or no access token was
    # captured. The API response is the source of truth for signed-in users.
    FALLBACK_MODELS = [
      { model_id: "gemini-3.8-flash-high", display_name: "Gemini 3.8 Flash (High)" },
      { model_id: "gemini-3.8-flash-medium", display_name: "Gemini 3.8 Flash (Medium)" },
      { model_id: "gemini-3.7-flash-high", display_name: "Gemini 3.7 Flash (High)" },
      { model_id: "gemini-3.7-flash-medium", display_name: "Gemini 3.7 Flash (Medium)" },
      { model_id: "gemini-3.6-flash-high", display_name: "Gemini 3.6 Flash (High)" },
      { model_id: "gemini-3.6-flash-medium", display_name: "Gemini 3.6 Flash (Medium)" },
      { model_id: "gemini-3.1-pro-high", display_name: "Gemini 3.1 Pro (High)" },
      { model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6 (Thinking)" },
      { model_id: "claude-opus-4-6-thinking", display_name: "Claude Opus 4.6 (Thinking)" },
      { model_id: "gpt-oss-120b-medium", display_name: "GPT-OSS 120B (Medium)" }
    ].freeze

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

    def default_env_vars(_session)
      { "AGY_CLI_HIDE_LOGO" => "1" }
    end

    def fetch_available_models(credentials, credential: nil)
      fetch_available_models_with_source(credentials, credential: credential)[:models]
    end

    def fetch_available_models_with_source(credentials, credential: nil)
      access_token = credentials["access_token"]
      return fallback_models if access_token.blank?

      uri = URI(MODELS_URL)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["Content-Type"] = "application/json"
      request["Accept-Encoding"] = "gzip"
      request.body = { project: CONSUMER_PROJECT }.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
      return fallback_models unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response_body(response))
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
      parts += [ "--print", "--output-format", "stream-json" ] if mode == "non_interactive"
      parts.join(" ")
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

    def fallback_models
      { models: FALLBACK_MODELS, source: :fallback }
    end

    def response_body(response)
      return response.body unless response["Content-Encoding"].to_s.downcase.include?("gzip")

      Zlib::GzipReader.new(StringIO.new(response.body)).read
    end

    def settings
      # Omitting modelProvider selects Antigravity's OAuth-backed default
      # backend. Explicitly selecting "gemini" instead requires GEMINI_API_KEY.
      { "enableTelemetry" => false, "showTips" => false }
    end
  end
end
