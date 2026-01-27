# frozen_string_literal: true

# Facade service for agent-specific credential operations
# Delegates to appropriate adapter based on agent type
class AgentCredentialsService
  ADAPTERS = {
    "claude_code" => Agents::ClaudeCodeAdapter,
    "cursor_cli" => Agents::CursorCliAdapter,
    "codex" => Agents::CodexAdapter,
    "gemini_cli" => Agents::GeminiCliAdapter
  }.freeze

  attr_reader :adapter, :agent_type

  def initialize(agent_type)
    @agent_type = agent_type
    adapter_class = ADAPTERS[agent_type]
    raise ArgumentError, "Unknown agent type: #{agent_type}" unless adapter_class

    @adapter = adapter_class.new
  end

  # Delegate core methods to adapter
  delegate :config_path, :home_dir, :auth_watch_path, :auth_required_keys,
           :auth_complete?, :extract_credentials, :generate_config, :config_files, to: :adapter

  # --- High-level operations ---

  # Extract credentials from a running container
  # @param container_id [String] Docker container ID
  # @return [Hash] extracted credentials
  def extract_from_container(container_id)
    content = read_container_file(container_id, config_path)
    return {} if content.blank?

    extract_credentials(content)
  end

  # Check if auth is complete in a running container
  # @param container_id [String] Docker container ID
  # @return [Boolean]
  def auth_complete_in_container?(container_id)
    content = read_container_file(container_id, config_path)
    return false if content.blank?

    auth_complete?(content)
  end

  # Write credentials to a running container
  # @param container_id [String] Docker container ID
  # @param credentials [Hash] credentials to write
  # @param workflow_config [Hash] optional workflow-specific settings
  def write_to_container(container_id, credentials, workflow_config = {})
    files = config_files(credentials, workflow_config)

    files.each do |path, content|
      write_container_file(container_id, path, content)
    end
  end

  # Save credentials from container to database
  # @param user [User] user to save credentials for
  # @param container_id [String] Docker container ID
  # @return [AgentCredential]
  def save_credentials_from_container(user, container_id)
    credentials = extract_from_container(container_id)
    raise "No credentials found in container" if credentials.blank?

    AgentCredential.from_artifacts(user.id, agent_type, credentials)
  end

  # Load credentials from database and write to container
  # @param user [User] user to load credentials for
  # @param container_id [String] Docker container ID
  # @param workflow_config [Hash] optional workflow-specific settings
  def load_credentials_to_container(user, container_id, workflow_config = {})
    credential = user.agent_credentials.find_by(agent_type: agent_type)
    raise "No credentials found for #{agent_type}" unless credential

    write_to_container(container_id, credential.config_data, workflow_config)
    credential.touch(:last_used_at)
  end

  # --- Class methods ---

  class << self
    def for(agent_type)
      new(agent_type)
    end

    def supported_agents
      ADAPTERS.keys
    end

    def supported?(agent_type)
      ADAPTERS.key?(agent_type)
    end
  end

  private

  def read_container_file(container_id, path)
    container = Docker::Container.get(container_id)
    # Read file content using exec
    # exec returns [stdout_array, stderr_array, exit_code]
    result = container.exec([ "cat", path ])
    stdout = result[0]
    exit_code = result[2]

    return nil unless exit_code.zero?

    stdout.join
  rescue Docker::Error::NotFoundError
    Rails.logger.warn("Container not found: #{container_id}")
    nil
  rescue StandardError => e
    Rails.logger.error("Failed to read #{path} from container #{container_id}: #{e.message}")
    nil
  end

  def write_container_file(container_id, path, content)
    container = Docker::Container.get(container_id)
    dir = File.dirname(path)

    # Create directory
    container.exec([ "mkdir", "-p", dir ])

    # Write file using base64 to handle special characters
    encoded = Base64.strict_encode64(content)
    container.exec([ "sh", "-c", "echo '#{encoded}' | base64 -d > #{path}" ])

    Rails.logger.info("Wrote #{path} to container #{container_id}")
  rescue StandardError => e
    Rails.logger.error("Failed to write #{path} to container #{container_id}: #{e.message}")
    raise
  end
end
