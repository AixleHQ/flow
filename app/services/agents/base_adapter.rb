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

    # Config files to write before auth starts (no credentials needed).
    # Used by AgentAuthStrategy#before_exec.
    # @return [Hash<String, String>] path => content
    def auth_setup_files
      {}
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

    # UID of the container user (used for file ownership in tar headers)
    # @return [Integer]
    def container_uid
      1001
    end

    # =================================================================
    # Session Command (mode-aware CLI command for ttyd)
    # =================================================================

    # Generate CLI command for the session based on mode.
    # @param mode [String] "interactive" or "non_interactive"
    # @param prompt [String, nil] initial prompt for non_interactive mode
    # @param model [String, nil] requested model ID (nil = runtime default)
    # @return [String] CLI command string
    def session_command(mode:, prompt: nil, model: nil)
      raise NotImplementedError, "#{self.class} must implement #session_command"
    end

    # =================================================================
    # Context File (CLI-specific instruction file auto-read at startup)
    # =================================================================

    # Path to CLI-specific context file (auto-read by CLI at startup).
    # Written to home dir (not workspace) to keep /workspace clean.
    # @return [String, nil] nil if CLI doesn't support context files
    def context_file_path
      nil
    end

    # =================================================================
    # Skill Installation (via npx skills add)
    # Skills are installed globally using the skills.sh CLI tool.
    # =================================================================

    # Whether skills are embedded directly into the context file (AGENTS.md).
    # When true, npx skills add is skipped and skills are merged into context.
    # @return [Boolean]
    def includes_skills_in_context?
      false
    end

    # Agent name for `npx skills add --agent <name>`.
    # Maps to the skills.sh ecosystem agent identifiers.
    # @return [String]
    def skills_agent_name
      raise NotImplementedError, "#{self.class} must implement #skills_agent_name"
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

    # Default environment variables for the container runtime.
    # @param session [TerminalSession, nil]
    # @return [Hash<String, String>]
    def default_env_vars(_session = nil)
      {}
    end

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

    # Parse and persist usage statistics for a terminal session.
    # Called on each OTLP trace payload (hooks, native traces).
    # @param payload [Hash] parsed OTLP JSON payload
    # @param terminal_session [TerminalSession]
    # @return [Symbol] :ok when persisted, :accepted when no usage found
    def ingest_usage(_payload, _terminal_session)
      pp _payload
    end

    # =================================================================
    # Available Models (fetched from provider API)
    # =================================================================

    # Fetch available models from the provider API using user credentials.
    # @param credentials [Hash] decrypted credential data from AgentCredential
    # @param credential [AgentCredential, nil] optional record for token refresh
    # @return [Array<Hash>] normalized models: [{ model_id:, display_name:, description: }]
    def fetch_available_models(_credentials, credential: nil)
      []
    end

    # Fetch models with source indicator for cache decisions.
    # @return [Hash{ models: Array<Hash>, source: Symbol }] source is :api or :fallback
    def fetch_available_models_with_source(credentials, credential: nil)
      { models: fetch_available_models(credentials, credential: credential), source: :api }
    end

    # =================================================================
    # Usage Collection (called once at session cleanup)
    # =================================================================

    # Domains tracked by MITM proxy for usage logging.
    # Empty = log all traffic (default for agents without usage tracking).
    # @return [Array<String>]
    def mitm_tracked_domains
      []
    end

    # Log files inside container to collect as artifacts after session ends.
    # @return [Array<String>]
    def session_log_paths
      %w[/var/log/context.log]
    end

    # Collect and verify usage data at session cleanup.
    # Called from AgentSessionStrategy#before_cleanup after artifact collection.
    # @param terminal_session [TerminalSession]
    # @param artifacts [Hash<String, String>] collected artifacts (path => content)
    def collect_usage(_terminal_session, _artifacts = {})
      # No-op by default. Override in adapters with usage tracking.
    end

    protected

    def parse_json(content)
      JSON.parse(content)
    rescue JSON::ParserError
      {}
    end
  end
end
