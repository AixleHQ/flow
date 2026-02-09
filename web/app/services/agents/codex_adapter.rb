# frozen_string_literal: true

module Agents
  # OpenAI Codex CLI adapter for credential handling
  # Config: ~/.codex/auth.json + ~/.codex/config.toml
  # Auth: OAuth via OpenAI (Google login)
  class CodexAdapter < BaseAdapter
    def self.default_config_paths
      [ "~/.codex/config.toml", "AGENTS.md" ]
    end

    def config_path
      "#{home_dir}/.codex/auth.json"
    end

    def home_dir
      "/home/codex"
    end

    # Keys that indicate auth is complete
    def auth_required_keys
      %w[tokens]
    end

    def auth_complete?(config_content)
      config = parse_json(config_content)
      tokens = config["tokens"]
      return false unless tokens.is_a?(Hash)

      # Auth complete if we have access_token or refresh_token
      tokens["access_token"].present? || tokens["refresh_token"].present?
    end

    # Extract only the credentials we need to persist
    def extract_credentials(config_content)
      config = parse_json(config_content)
      config.slice(
        "tokens",         # OAuth tokens (access, refresh, id)
        "OPENAI_API_KEY", # API key if set
        "account_id",     # Account identifier
        "last_refresh"    # Last token refresh time
      ).compact
    end

    # Generate auth.json config for a new container
    def generate_config(credentials, workflow_config = {})
      {
        **credentials,
        "last_refresh" => credentials["last_refresh"] || Time.current.iso8601
      }
    end

    # Override to write multiple config files
    def config_files(credentials, workflow_config = {})
      {
        # Auth credentials
        config_path => generate_config(credentials, workflow_config).to_json,
        # Project trust config (skip trust dialog)
        "#{home_dir}/.codex/config.toml" => generate_config_toml(workflow_config)
      }
    end

    # Context file: ~/.codex/AGENTS.md (auto-read by Codex at startup)
    def context_file_path
      "#{home_dir}/.codex/AGENTS.md"
    end

    # Skill files: ~/.codex/skills/<name>/SKILL.md with YAML front matter (user-scoped)
    def skill_files(skills)
      files = {}
      skills.each do |skill|
        next if skill.content.blank?

        description = (skill.description || skill.title || skill.name).to_s
        front_matter = "---\nname: #{skill.name}\ndescription: #{description.to_json}\n---\n\n"
        files["#{home_dir}/.codex/skills/#{skill.name}/SKILL.md"] = front_matter + skill.content
      end
      files
    end

    # MCP config: appended to ~/.codex/config.toml
    def mcp_config(servers)
      sections = servers.map do |s|
        lines = []
        lines << "[mcp_servers.\"#{s.name}\"]"
        lines << "type = \"#{s.transport == 'sse' ? 'http' : 'stdio'}\""
        lines << "url = \"#{s.url}\"" if s.url.present?
        if s.headers.present? && s.headers.any?
          header_pairs = s.headers.map { |k, v| "#{k} = \"#{v}\"" }.join(", ")
          lines << "headers = { #{header_pairs} }"
        end
        lines.join("\n")
      end
      { "#{home_dir}/.codex/config.toml" => "# MCP Servers (auto-generated)\n#{sections.join("\n\n")}\n" }
    end

    def mcp_merge_strategy
      :append_toml
    end

    private

    def generate_config_toml(workflow_config)
      workspace = workflow_config[:workspace] || "/workspace"
      <<~TOML
        # Auto-approve all commands without asking
        approval_policy = "never"

        # Full filesystem and network access
        sandbox_mode = "danger-full-access"

        [projects."#{workspace}"]
        trust_level = "trusted"

        [notice]
        hide_full_access_warning = true
      TOML
    end
  end
end
