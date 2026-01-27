# frozen_string_literal: true

module Agents
  # Cursor CLI adapter for credential handling
  # Config files:
  #   - ~/.config/cursor/auth.json (tokens)
  #   - ~/.cursor/cli-config.json (settings)
  # Auth: OAuth via Cursor (agent login)
  class CursorCliAdapter < BaseAdapter
    def config_path
      # Primary auth file
      "#{home_dir}/.config/cursor/auth.json"
    end

    def home_dir
      "/home/cursor"
    end

    # Keys that indicate auth is complete
    def auth_required_keys
      %w[accessToken]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      config["accessToken"].present?
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice("accessToken", "refreshToken").compact
    end

    # Generate auth.json for a new container
    def generate_config(credentials, workflow_config = {})
      {
        "accessToken" => credentials["accessToken"],
        "refreshToken" => credentials["refreshToken"]
      }.compact
    end

    # Override to write multiple config files
    def config_files(credentials, workflow_config = {})
      workspace = workflow_config[:workspace] || "/workspace"
      {
        # Auth tokens
        config_path => generate_config(credentials, workflow_config).to_json,
        # CLI settings with full permissions
        "#{home_dir}/.cursor/cli-config.json" => generate_cli_config(workflow_config).to_json,
        # Workspace trust (skip trust dialog)
        "#{home_dir}/.cursor/projects#{workspace}/.workspace-trusted" => generate_workspace_trust(workspace).to_json
      }
    end

    # Only mount config directories as tmpfs, not entire home
    # This preserves /home/cursor/.local/bin/agent binary installed in Dockerfile
    def tmpfs_paths
      [
        "#{home_dir}/.config/cursor",  # auth.json location
        "#{home_dir}/.cursor"          # cli-config.json location
      ]
    end

    private

    def generate_cli_config(workflow_config)
      {
        "permissions" => {
          "allow" => ["*"],  # Allow all commands
          "deny" => []
        },
        "version" => 1,
        "editor" => {
          "vimMode" => false
        },
        "hasChangedDefaultModel" => false,
        "privacyCache" => {
          "ghostMode" => true,
          "privacyMode" => 2,
          "updatedAt" => (Time.current.to_f * 1000).to_i
        },
        "network" => {
          "useHttp1ForAgent" => false
        },
        "approvalMode" => "auto-edit",  # Auto-approve edits
        "sandbox" => {
          "mode" => "disabled",         # Disable sandbox
          "networkAccess" => "all"      # Allow all network
        },
        "attribution" => {
          "attributeCommitsToAgent" => true,
          "attributePRsToAgent" => true
        }
      }
    end

    def generate_workspace_trust(workspace)
      {
        "trustedAt" => Time.current.iso8601(3),
        "workspacePath" => workspace
      }
    end
  end
end
