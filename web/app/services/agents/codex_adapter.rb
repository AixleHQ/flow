# frozen_string_literal: true

module Agents
  # OpenAI Codex CLI adapter for credential handling
  # TODO: Research actual config paths and format
  class CodexAdapter < BaseAdapter
    def config_path
      "#{home_dir}/.codex/config.json"
    end

    def home_dir
      "/home/codex"
    end

    def auth_required_keys
      %w[apiKey]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      # TODO: Implement actual auth detection logic
      config["apiKey"].present?
    end

    def extract_credentials(config_content)
      config = parse_json(config_content)
      # TODO: Determine actual credential fields
      config.slice("apiKey", "organizationId").compact
    end

    def generate_config(credentials, workflow_config = {})
      {
        **credentials,
        # TODO: Add Codex-specific config generation
        "workspace" => "/workspace"
      }
    end
  end
end
