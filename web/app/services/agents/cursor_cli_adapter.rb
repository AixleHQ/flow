# frozen_string_literal: true

module Agents
  # Cursor CLI adapter for credential handling
  # Config files:
  #   - ~/.config/cursor/auth.json (tokens)
  #   - ~/.cursor/cli-config.json (settings)
  # Auth: OAuth via Cursor (agent login)
  class CursorCliAdapter < BaseAdapter
    def self.default_config_paths
      [ "~/.cursor/cli-config.json", ".cursorrules" ]
    end

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

    # Session command: agent (interactive), agent -m "prompt" (non-interactive)
    def session_command(mode:, prompt: nil)
      if mode == "non_interactive" && prompt.present?
        "agent -m #{Shellwords.escape(prompt)}"
      else
        "agent"
      end
    end

    # Context file: ~/.cursor/rules/.cursorrules (auto-read by Cursor at startup)
    def context_file_path
      "#{home_dir}/.cursor/rules/.cursorrules"
    end

    # Skill files: ~/.cursor/rules/<name>.md (user-scoped, not in workspace)
    def skill_files(skills)
      files = {}
      skills.each do |skill|
        next if skill.content.blank?

        files["#{home_dir}/.cursor/rules/#{skill.name}.md"] = skill.content
      end
      files
    end

    # MCP config: /workspace/.cursor/mcp.json
    def mcp_config(servers)
      mcp_servers = {}
      servers.each do |s|
        entry = {}
        entry["url"] = s.url if s.url.present?
        entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        mcp_servers[s.name] = entry
      end
      { "/workspace/.cursor/mcp.json" => { "mcpServers" => mcp_servers }.to_json }
    end

    # Only mount config directories as tmpfs, not entire home
    # This preserves /home/cursor/.local/bin/agent binary installed in Dockerfile
    def tmpfs_paths
      [
        "#{home_dir}/.config/cursor",  # auth.json location
        "#{home_dir}/.cursor",         # cli-config.json location
        "#{home_dir}/.mitmproxy"       # MITM proxy CA certificates
      ]
    end

    private

    def generate_cli_config(workflow_config)
      {
        # Required fields per docs
        "version" => 1,
        "editor" => {
          "vimMode" => false
        },
        "permissions" => {
          # Allow common dev commands
          "allow" => [
            "Shell(ls)", "Shell(cat)", "Shell(head)", "Shell(tail)", "Shell(grep)", "Shell(find)",
            "Shell(git)", "Shell(npm)", "Shell(yarn)", "Shell(pnpm)", "Shell(node)",
            "Shell(python)", "Shell(pip)", "Shell(python3)", "Shell(pip3)",
            "Shell(ruby)", "Shell(bundle)", "Shell(rails)", "Shell(rake)",
            "Shell(make)", "Shell(cargo)", "Shell(go)",
            "Shell(curl)", "Shell(wget)",
            "Shell(mkdir)", "Shell(cp)", "Shell(mv)", "Shell(touch)",
            "Shell(echo)", "Shell(pwd)", "Shell(cd)", "Shell(tree)",
            "Read(**/*)",   # Allow reading all files
            "Write(**/*)"   # Allow writing all files
          ],
          # Deny dangerous commands
          "deny" => [
            "Shell(rm)",    # Prevent destructive removal
            "Shell(sudo)",  # No privilege escalation
            "Read(.env*)",  # Protect env files from reading
            "Write(.env*)"  # Protect env files from writing
          ]
        },
        # Optional fields
        "hasChangedDefaultModel" => false,
        "network" => {
          "useHttp1ForAgent" => false  # Better proxy compatibility
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
