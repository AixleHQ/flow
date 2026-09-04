# frozen_string_literal: true

require "shellwords"

module Agents
  # Google Antigravity CLI adapter.
  #
  # Aixle intentionally supports the documented Gemini API-key provider only. It is
  # the one Antigravity auth mode that is portable across ephemeral containers and
  # works headlessly; account OAuth is stored in the host keyring and is unsuitable
  # for copying between isolated sessions.
  #
  # Unlike every other adapter's login, `agy`'s API-key mode has no interactive
  # credential prompt of its own to run inside the auth terminal: confirmed against
  # the real 1.1.x binary, it only reads GEMINI_API_KEY from the environment at
  # startup and exits immediately with an error if that is unset — it never writes a
  # credential artifact for this mode. So the auth-terminal session (see
  # #auth_launch_commands_for) runs a small login script instead of `agy` directly:
  # it reads the key the user types, calls the real CLI to validate it, and — only on
  # success — writes it to the same file every other step here already assumes
  # (#config_path). That keeps credential capture on the one shared path
  # (AgentAuthStrategy#before_cleanup reads #auth_file_paths) instead of a bespoke
  # backend form, while still requiring a live human to supply and verify the secret.
  class AntigravityCliAdapter < BaseAdapter
    SETTINGS_PATH = ".gemini/antigravity-cli/settings.json"
    API_KEY_PATH = ".gemini/antigravity-cli/aixle-api-key.json"
    LOGIN_SCRIPT_PATH = ".aixle/antigravity-login.sh"

    def self.default_config_paths
      [ "~/.gemini/antigravity-cli/settings.json", "~/.gemini/config/mcp_config.json", "GEMINI.md" ]
    end

    def home_dir = "/home/antigravity"
    def config_path = "#{home_dir}/#{API_KEY_PATH}"
    def auth_file_paths = [ config_path ]
    def auth_required_keys = %w[api_key]

    def auth_complete?(content)
      parse_json(content)["api_key"].present?
    end

    def extract_credentials(content)
      key = parse_json(content)["api_key"]
      key.present? ? { "api_key" => key } : {}
    end

    def generate_config(credentials, _workflow_config = {})
      { "api_key" => credentials["api_key"] }
    end

    def config_files(credentials, _workflow_config = {})
      {
        "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json,
        config_path => generate_config(credentials).to_json
      }
    end

    def auth_setup_files
      {
        "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json,
        "#{home_dir}/#{LOGIN_SCRIPT_PATH}" => login_script
      }
    end

    # Drives the auth terminal: AgentAuthStrategy starts `bash` (see
    # AgentAuthStrategy#ttyd_command) and sends this once the prompt is ready, in
    # place of launching `agy` directly. The script itself is what the user watches
    # and types into — this only launches it.
    def auth_launch_commands_for(_kind)
      [ "sh #{home_dir}/#{LOGIN_SCRIPT_PATH}" ]
    end

    def default_env_vars(session)
      credential = SessionCompany.agent_credentials_for(session).find_by(agent_type: "antigravity_cli")
      { "GEMINI_API_KEY" => credential&.config_data&.dig("api_key"), "AGY_CLI_HIDE_LOGO" => "1" }.compact
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

    # Prompts for the key (masked, real terminal input — never seen by Aixle's
    # backend), validates it with a real `agy` call, and writes #config_path only on
    # success. Re-running `sh ~/#{LOGIN_SCRIPT_PATH}` retries a rejected or empty
    # entry; nothing here persists partial state that a retry would need to undo.
    #
    # Single-quoted heredoc: the script is shell, not Ruby, so none of its own `\`/`"`
    # escaping should go through Ruby's string-escape processing. The two paths are
    # substituted afterwards via plain token replacement instead of interpolation.
    def login_script
      template = <<~'SCRIPT'
        #!/bin/sh
        set -eu
        echo "Paste your company's Google AI Studio API key (https://aistudio.google.com/app/api-keys), then press Enter:"
        stty -echo 2>/dev/null || true
        IFS= read -r key
        stty echo 2>/dev/null || true
        echo
        if [ -z "$key" ]; then
          echo "No key entered. Run 'sh ~/__LOGIN_SCRIPT_PATH__' to try again."
          exit 1
        fi
        if ! GEMINI_API_KEY="$key" agy --print "Reply with OK if you can read this." >/tmp/antigravity-auth-check.log 2>&1; then
          echo "Google AI Studio rejected that key:"
          cat /tmp/antigravity-auth-check.log
          echo "Run 'sh ~/__LOGIN_SCRIPT_PATH__' to try again."
          exit 1
        fi
        escaped_key=$(printf '%s' "$key" | sed 's/\\/\\\\/g; s/"/\\"/g')
        mkdir -p "$(dirname "$HOME/__API_KEY_PATH__")"
        printf '{"api_key":"%s"}' "$escaped_key" > "$HOME/__API_KEY_PATH__"
        echo "Key verified -- Aixle will finish saving it automatically."
      SCRIPT

      template.gsub("__LOGIN_SCRIPT_PATH__", LOGIN_SCRIPT_PATH).gsub("__API_KEY_PATH__", API_KEY_PATH)
    end
  end
end
