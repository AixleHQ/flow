# frozen_string_literal: true

require "shellwords"

module Agents
  # Google Antigravity CLI adapter.
  #
  # Auth model (confirmed against the real 1.1.27 `agy` binary): run with no flags
  # and no GEMINI_API_KEY, its interactive welcome prompt only offers "Google
  # OAuth" or "Use a Google Cloud project" — both end up going through the same
  # Google OAuth authorization-code flow (just different scopes), and neither
  # offers a raw-API-key option. That flow uses a Google-hosted redirect
  # (`https://antigravity.google/oauth-callback`), not a localhost callback, so it
  # never needs the container to receive anything: the user opens the printed URL
  # in their own browser and either gets redirected straight through, or pastes
  # the resulting authorization code back into the terminal by hand. And in a
  # container specifically — confirmed via the CLI's own log output
  # ("composite_token_storage.go: Using file-based token storage because no D-Bus
  # session bus detected") — `agy` automatically persists the login to a file
  # instead of the host OS keyring, exactly like every other adapter's CLI-driven
  # login here. So, per review feedback, this adapter drives the real `agy` login
  # directly (default #auth_launch_commands_for, same as Gemini/Codex/Claude)
  # instead of a bespoke script, and captures whatever `agy` writes under its own
  # config directory — mirroring GeminiCliAdapter's `~/.gemini/oauth_creds.json`
  # (both CLIs share the same underlying Google "codeassistclient" auth library),
  # namespaced the same way Antigravity already namespaces its settings file.
  #
  # The exact on-disk filename could not be confirmed end-to-end here without
  # completing a real Google OAuth grant (no test account available in this
  # environment) — only the container-vs-keyring fallback behavior and the
  # settings/config directory layout were. If a live login in the built image
  # writes the token somewhere else, only OAUTH_CREDS_PATH below needs to change.
  class AntigravityCliAdapter < BaseAdapter
    SETTINGS_PATH = ".gemini/antigravity-cli/settings.json"
    OAUTH_CREDS_PATH = ".gemini/antigravity-cli/oauth_creds.json"

    def self.default_config_paths
      [ "~/.gemini/antigravity-cli/settings.json", "~/.gemini/config/mcp_config.json", "GEMINI.md" ]
    end

    def home_dir = "/home/antigravity"
    def config_path = "#{home_dir}/#{OAUTH_CREDS_PATH}"

    # Watch the OAuth token file, not settings.json: settings.json is written
    # up front by #auth_setup_files, before the user has logged in at all, so
    # watching it would report success prematurely.
    def auth_watch_path = config_path

    def auth_file_paths = [ config_path, "#{home_dir}/#{SETTINGS_PATH}" ]
    def auth_required_keys = %w[access_token]

    def auth_complete?(content)
      parse_json(content)["access_token"].present?
    end

    def extract_credentials(content)
      parse_json(content).slice("access_token", "refresh_token", "token_type", "expiry", "id_token").compact
    end

    def generate_config(credentials, _workflow_config = {})
      credentials
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

    def settings
      { "modelProvider" => "gemini", "enableTelemetry" => false, "showTips" => false }
    end
  end
end
