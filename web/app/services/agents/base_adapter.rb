# frozen_string_literal: true

module Agents
  # Base adapter interface for agent-specific credential handling
  # Each agent (Claude Code, Cursor CLI, etc.) has different config formats and paths
  class BaseAdapter
    # Path to main config file inside container
    # @return [String]
    def config_path
      raise NotImplementedError, "#{self.class} must implement #config_path"
    end

    # Home directory inside container
    # @return [String]
    def home_dir
      raise NotImplementedError, "#{self.class} must implement #home_dir"
    end

    # Default config file paths for UI hints (path => description)
    # @return [Array<String>]
    def self.default_config_paths
      []
    end

    # Path to watch for auth completion (for watcher service)
    # @return [String]
    def auth_watch_path
      config_path
    end

    # Keys to check for auth completion (any key present = auth complete)
    # Supports nested keys like "oauthAccount.accountUuid"
    # @return [Array<String>]
    def auth_required_keys
      raise NotImplementedError, "#{self.class} must implement #auth_required_keys"
    end

    # Check if authentication is complete based on config content
    # @param config_content [String] raw config file content
    # @return [Boolean]
    def auth_complete?(config_content)
      raise NotImplementedError, "#{self.class} must implement #auth_complete?"
    end

    # Extract credentials from config content (only fields we need to persist)
    # @param config_content [String] raw config file content
    # @return [Hash] credentials to store in database
    def extract_credentials(config_content)
      raise NotImplementedError, "#{self.class} must implement #extract_credentials"
    end

    # Generate full config file content for a new container
    # @param credentials [Hash] stored credentials from database
    # @param workflow_config [Hash] optional workflow-specific settings (tools, MCP, etc.)
    # @return [Hash] full config to write to container
    def generate_config(credentials, workflow_config = {})
      raise NotImplementedError, "#{self.class} must implement #generate_config"
    end

    # List of config files to write to container (path => content)
    # Override if agent needs multiple config files
    # @param credentials [Hash] stored credentials from database
    # @param workflow_config [Hash] optional workflow-specific settings
    # @return [Hash<String, String>] path => content mapping
    def config_files(credentials, workflow_config = {})
      {
        config_path => generate_config(credentials, workflow_config).to_json
      }
    end

    # Paths to mount as tmpfs (for ephemeral credentials storage)
    # By default, mounts entire home directory
    # Override for agents that install binaries in home (e.g., Cursor CLI)
    # @return [Array<String>]
    def tmpfs_paths
      [ home_dir ]
    end

    # UID for tmpfs mounts (must match container user)
    # @return [Integer]
    def tmpfs_uid
      1001
    end

    # =================================================================
    # MCP Server Configuration
    # Each CLI has different MCP config format and file path
    # =================================================================

    # Generate MCP config files for this CLI.
    # @param servers [Array<OpenStruct>] resolved servers with :name, :url, :transport, :headers
    # @return [Hash<String, String>] { path => content }
    def mcp_config(servers)
      {}
    end

    # How to handle existing file at MCP config path.
    # :fresh       — write new file (Claude, Cursor)
    # :merge_json  — read existing JSON, merge mcpServers key, write back (Gemini)
    # :append_toml — read existing TOML, append MCP section (Codex)
    # @return [Symbol]
    def mcp_merge_strategy
      :fresh
    end

    # =================================================================
    # Environment Variables (from session/credential metadata)
    # Used for agent-specific config like GOOGLE_CLOUD_PROJECT
    # =================================================================

    # Fields that must be configured before starting container
    # Shown in UI before auth terminal starts
    # @return [Array<Hash>] list of field definitions
    # Example: [{ key: 'google_cloud_project', label: 'Google Project ID', required: true }]
    def required_env_fields
      []
    end

    # Extract environment variables from metadata (session or credential)
    # @param metadata [Hash] metadata hash
    # @return [Hash<String, String>] env var name => value
    def env_vars_from_metadata(metadata)
      {}
    end

    # Validate that required env fields are present in metadata
    # @param metadata [Hash] metadata hash
    # @return [Array<String>] list of error messages (empty if valid)
    def validate_metadata(metadata)
      missing = required_env_fields
                .select { |f| f[:required] && metadata[f[:key]].blank? }
                .map { |f| "#{f[:label]} is required" }
      missing
    end

    # Check if agent requires env fields before starting
    # @return [Boolean]
    def requires_env_fields?
      required_env_fields.any? { |f| f[:required] }
    end

    protected

    def parse_json(content)
      JSON.parse(content)
    rescue JSON::ParserError
      {}
    end
  end
end
