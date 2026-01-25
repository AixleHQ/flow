# frozen_string_literal: true

# AgentCredential - Stores encrypted authentication artifacts for agents
class AgentCredential < ApplicationRecord
  belongs_to :user

  # Validations
  validates :agent_type, presence: true, inclusion: {
    in: %w[claude_code cursor_cli codex gemini_cli],
    message: "%{value} is not a valid agent type"
  }
  validates :agent_type, uniqueness: { scope: :user_id }
  validates :encrypted_config_data, presence: true

  # Scopes
  scope :for_agent, ->(agent_type) { where(agent_type: agent_type) }
  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Create credential from collected artifacts
  def self.from_artifacts(user_id, agent_type, artifacts_hash)
    credential = find_or_initialize_by(user_id: user_id, agent_type: agent_type)
    credential.config_data = artifacts_hash
    credential.metadata = {
      collected_at: Time.current,
      artifact_keys: artifacts_hash.keys
    }
    credential.save!
    credential
  end

  # Get decrypted config data as hash
  def config_data
    return {} if encrypted_config_data.blank?

    decrypted = encryptor.decrypt_and_verify(encrypted_config_data)
    JSON.parse(decrypted)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, JSON::ParserError, TypeError
    # Fallback: try reading as plain JSON (for existing unencrypted data)
    JSON.parse(encrypted_config_data) rescue {}
  end

  # Set config data (will be encrypted)
  def config_data=(hash)
    self.encrypted_config_data = encryptor.encrypt_and_sign(hash.to_json)
  end

  # Get adapter for this agent type
  def adapter
    @adapter ||= AgentCredentialsService.for(agent_type).adapter
  end

  # Generate full config for a container
  def generate_container_config(workflow_config = {})
    adapter.generate_config(config_data, workflow_config)
  end

  # Write credentials to a running container
  def write_to_container(container_id, workflow_config = {})
    service = AgentCredentialsService.for(agent_type)
    service.write_to_container(container_id, config_data, workflow_config)
    touch(:last_used_at)
  end

  private

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(encryption_key)
  end

  def encryption_key
    # Key must be exactly 32 bytes for AES-256
    Settings.encryption.credentials_key.to_s.ljust(32, "0")[0..31]
  end
end
