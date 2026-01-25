# frozen_string_literal: true

module Agents
  # Cursor CLI adapter for credential handling
  # TODO: Research actual config paths and format
  class CursorCliAdapter < BaseAdapter
    def config_path
      "#{home_dir}/.cursor/config.json"
    end

    def home_dir
      "/home/cursor"
    end

    def auth_required_keys
      %w[accessToken apiKey]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      # TODO: Implement actual auth detection logic
      config["accessToken"].present? || config["apiKey"].present?
    end

    def extract_credentials(config_content)
      config = parse_json(config_content)
      # TODO: Determine actual credential fields
      config.slice("accessToken", "apiKey", "userId").compact
    end

    def generate_config(credentials, workflow_config = {})
      {
        **credentials,
        # TODO: Add Cursor-specific config generation
        "workspace" => "/workspace"
      }
    end
  end
end
