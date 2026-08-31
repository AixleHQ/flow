# frozen_string_literal: true

require "shellwords"

module Agents
  # Google Antigravity CLI adapter.
  #
  # Aixle intentionally supports the documented Gemini API-key provider only. It is
  # the one Antigravity auth mode that is portable across ephemeral containers and
  # works headlessly; account OAuth is stored in the host keyring and is unsuitable
  # for copying between isolated sessions.
  class AntigravityCliAdapter < BaseAdapter
    SETTINGS_PATH = ".gemini/antigravity-cli/settings.json"
    API_KEY_PATH = ".gemini/antigravity-cli/aixle-api-key.json"

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
      { "#{home_dir}/#{SETTINGS_PATH}" => settings.to_json }
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
  end
end
