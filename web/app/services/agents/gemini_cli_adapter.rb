# frozen_string_literal: true

module Agents
  # Google Gemini CLI adapter for credential handling
  # Gemini CLI requires GOOGLE_CLOUD_PROJECT environment variable BEFORE starting
  #
  # Config structure (discovered from container):
  #   ~/.gemini/oauth_creds.json - OAuth tokens (access_token, refresh_token, etc.)
  #   ~/.gemini/settings.json - Auth settings (selectedType: oauth-personal)
  #   ~/.gemini/google_accounts.json - Account info
  class GeminiCliAdapter < BaseAdapter
    def config_path
      "#{home_dir}/.gemini/oauth_creds.json"
    end

    def home_dir
      "/home/gemini"
    end

    def auth_required_keys
      %w[refresh_token]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      config["refresh_token"].present?
    end

    def extract_credentials(config_content)
      config = parse_json(config_content)
      # Extract OAuth credentials
      config.slice("access_token", "refresh_token", "scope", "token_type", "id_token", "expiry_date")
    end

    def generate_config(credentials, workflow_config = {})
      # Return OAuth credentials as-is for oauth_creds.json
      credentials
    end

    # Multiple config files needed for Gemini CLI
    def config_files(credentials, workflow_config = {})
      {
        # OAuth credentials
        "#{home_dir}/.gemini/oauth_creds.json" => credentials.to_json,
        # Settings to mark auth type and enable preview features
        "#{home_dir}/.gemini/settings.json" => {
          "security" => {
            "auth" => {
              "selectedType" => "oauth-personal"
            }
          },
          "general" => {
            "previewFeatures" => true
          }
        }.to_json
      }
    end

    # Directories to mount as tmpfs for credential storage
    def tmpfs_paths
      ["#{home_dir}/.gemini"]
    end

    # =================================================================
    # Environment Variables (from session/credential metadata)
    # =================================================================

    # Fields that must be configured before starting container
    def required_env_fields
      [
        { key: "google_cloud_project", label: "Google Cloud Project ID", required: true, placeholder: "my-project-123" }
      ]
    end

    # Convert metadata to environment variables for container
    def env_vars_from_metadata(metadata)
      {
        "GOOGLE_CLOUD_PROJECT" => metadata["google_cloud_project"]
      }.compact
    end
  end
end
