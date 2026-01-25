# frozen_string_literal: true

module Agents
  # Google Gemini CLI adapter for credential handling
  # TODO: Research actual config paths and format
  class GeminiCliAdapter < BaseAdapter
    def config_path
      "#{home_dir}/.config/gemini/config.json"
    end

    def home_dir
      "/home/gemini"
    end

    def auth_required_keys
      %w[apiKey credentials]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      # TODO: Implement actual auth detection logic
      config["apiKey"].present? || config["credentials"].present?
    end

    def extract_credentials(config_content)
      config = parse_json(config_content)
      # TODO: Determine actual credential fields
      config.slice("apiKey", "credentials", "projectId").compact
    end

    def generate_config(credentials, workflow_config = {})
      {
        **credentials,
        # TODO: Add Gemini-specific config generation
        "workspace" => "/workspace"
      }
    end
  end
end
