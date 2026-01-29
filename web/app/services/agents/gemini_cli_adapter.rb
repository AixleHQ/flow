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
        # Settings per https://geminicli.com/docs/get-started/configuration/
        "#{home_dir}/.gemini/settings.json" => generate_settings.to_json
      }
    end

    # Directories to mount as tmpfs for credential storage
    def tmpfs_paths
      [
        "#{home_dir}/.gemini",    # Gemini CLI config
        "#{home_dir}/.mitmproxy"  # MITM proxy CA certificates
      ]
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

    private

    def generate_settings
      {
        # Authentication
        "security" => {
          "auth" => {
            "selectedType" => "oauth-personal"
          },
          # Don't ask for folder trust in containers
          "folderTrust" => {
            "enabled" => false
          }
        },
        # General settings
        "general" => {
          "previewFeatures" => true,       # Enable preview models (gemini-3-*)
          "vimMode" => false,
          "enableAutoUpdate" => false,     # Disable auto-update in containers
          "enableAutoUpdateNotification" => false
        },
        # UI settings for headless/container environment
        "ui" => {
          "hideBanner" => true,
          "hideTips" => true,
          "hideWindowTitle" => true,
          "dynamicWindowTitle" => false,
          "showHomeDirectoryWarning" => false
        },
        # Privacy
        "privacy" => {
          "usageStatisticsEnabled" => true  # No telemetry in containers
        },
        # Tools - auto approve all operations (container is the sandbox)
        "tools" => {
          "autoAccept" => true,
          "approvalMode" => "yolo",          # Auto-approve ALL tools
          "sandbox" => false,                # Container is already sandboxed
          "useRipgrep" => true
        },
        # Experimental features
        "experimental" => {
          "useOSC52Paste" => true,           # Better paste in web terminal
          "enableAgents" => true             # Enable subagents
        }
      }
    end
  end
end
