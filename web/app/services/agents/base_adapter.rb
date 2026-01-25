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

    protected

    def parse_json(content)
      JSON.parse(content)
    rescue JSON::ParserError
      {}
    end
  end
end
