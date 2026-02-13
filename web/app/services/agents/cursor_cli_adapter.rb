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

    # Session command: agent --force (interactive), agent --force -p (non-interactive)
    # --force: auto-approve all tools unless explicitly denied (yolo mode)
    # Prompt value is passed via AGENT_PROMPT env var and /tmp/.agent_prompt file
    def session_command(mode:, prompt: nil)
      base = "agent --force"
      if mode == "non_interactive" && prompt.present?
        "#{base} -p"
      else
        base
      end
    end

    # Context file: /workspace/AGENTS.md (auto-read by Cursor at startup, no git required)
    def context_file_path
      "/workspace/AGENTS.md"
    end

    # Skills as standard Cursor Agent Skills: ~/.cursor/skills/<name>/SKILL.md
    # Cursor auto-discovers and applies them based on description relevance.
    # Adds YAML frontmatter (name, description) if not already present.
    # See: https://cursor.com/docs/context/skills
    def skill_files(skills)
      files = {}
      skills.each do |skill|
        next if skill.content.blank?

        slug = skill.name.parameterize
        content = ensure_skill_frontmatter(skill)
        files["#{home_dir}/.cursor/skills/#{slug}/SKILL.md"] = content
      end
      files
    end

    # MCP config: /workspace/.cursor/mcp.json + pre-approved mcp-approvals.json
    def mcp_config(servers)
      workspace = "/workspace"
      mcp_servers = {}
      approvals = []

      servers.each do |s|
        entry = {}
        entry["url"] = s.url if s.url.present?
        entry["headers"] = s.headers if s.headers.present? && s.headers.any?
        mcp_servers[s.name] = entry
        approvals << "#{s.name}-#{mcp_approval_hash(entry, workspace)}"
      end

      {
        "#{workspace}/.cursor/mcp.json" => { "mcpServers" => mcp_servers }.to_json,
        "#{home_dir}/.cursor/projects#{workspace}/mcp-approvals.json" => approvals.to_json
      }
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

    # Ensure SKILL.md has YAML frontmatter with name and description.
    # Skips if content already starts with ---.
    def ensure_skill_frontmatter(skill)
      content = skill.content.strip
      return content if content.start_with?("---")

      frontmatter = [
        "---",
        "name: #{skill.name.parameterize}",
        "description: #{(skill.description.presence || skill.title.presence || skill.name).to_s.gsub('"', '\\"')}",
        "---"
      ].join("\n")

      "#{frontmatter}\n\n#{content}"
    end

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
            "Read(**/*)",    # Allow reading all files
            "Write(**/*)",  # Allow writing all files
            "Mcp(*:*)",    # Allow all MCP server tools without confirmation
            "WebFetch(**)"  # Allow fetching any URL (** matches domains and paths)
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

    # Generate MCP approval hash matching Cursor CLI algorithm:
    # sha256(JSON.stringify({path: workspace, server: serverConfig})).substring(0, 16)
    def mcp_approval_hash(server_entry, workspace)
      payload = { "path" => workspace, "server" => server_entry }
      Digest::SHA256.hexdigest(payload.to_json)[0, 16]
    end
  end
end
