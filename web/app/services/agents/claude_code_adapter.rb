# frozen_string_literal: true

module Agents
  # Claude Code adapter for credential handling
  # Config: ~/.claude.json
  # Docs: https://docs.anthropic.com/claude-code
  class ClaudeCodeAdapter < BaseAdapter
    CONFIG_VERSION = "2.1.14"

    def config_path
      "#{home_dir}/.claude.json"
    end

    def home_dir
      "/home/claude"
    end

    # Keys that indicate auth is complete (any one = success)
    def auth_required_keys
      %w[oauthAccount primaryApiKey]
    end

    # Check if OAuth or API key is present
    def auth_complete?(config_content)
      config = parse_json(config_content)
      config["oauthAccount"].present? || config["primaryApiKey"].present?
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice(
        "oauthAccount",      # OAuth account info
        "primaryApiKey",     # API key
        "customApiKeyResponses", # approved/rejected API keys
        "userID"             # user identifier
      ).compact
    end

    # Generate full config for a new container
    def generate_config(credentials, workflow_config = {})
      {
        # Credentials from database
        **credentials,

        # Fixed values (skip onboarding, etc.)
        "installMethod" => "global",
        "hasCompletedOnboarding" => true,
        "lastOnboardingVersion" => CONFIG_VERSION,
        "numStartups" => 1,

        # Project config (generated based on workflow)
        "projects" => generate_projects_config(workflow_config)
      }
    end

    # Override to write multiple config files
    def config_files(credentials, workflow_config = {})
      {
        # Main config with credentials
        config_path => generate_config(credentials, workflow_config).to_json,
        # Settings to skip bypass permissions warning
        "#{home_dir}/.claude/settings.json" => generate_settings.to_json
      }
    end

    private

    def generate_settings
      {
        # Auto-accept the bypass permissions warning
        "permissions" => {
          "defaultMode" => "bypassPermissions",
          "allow" => ["*"],
          "deny" => [],
          "ask" => []
        },
        "bypassPermissionsWarningAccepted" => true,
      }
    end

    def generate_projects_config(workflow_config)
      {
        "/workspace" => {
          # Tools and MCP from workflow config
          "allowedTools" => workflow_config[:allowed_tools] || [],
          "mcpServers" => workflow_config[:mcp_servers] || {},
          "mcpContextUris" => workflow_config[:mcp_context_uris] || [],
          "enabledMcpjsonServers" => workflow_config[:enabled_mcp_servers] || [],
          "disabledMcpjsonServers" => workflow_config[:disabled_mcp_servers] || [],

          # Always trust workspace (skip dialog)
          "hasTrustDialogAccepted" => true,
          "projectOnboardingSeenCount" => 1,

          # External includes (security)
          "hasClaudeMdExternalIncludesApproved" => false,
          "hasClaudeMdExternalIncludesWarningShown" => false,

          # Vulnerability cache (will be populated at runtime)
          "reactVulnerabilityCache" => {
            "detected" => false,
            "package" => nil,
            "packageName" => nil,
            "version" => nil,
            "packageManager" => nil
          }
        }
      }
    end
  end
end
