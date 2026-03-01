# frozen_string_literal: true

# AgentCredential - Stores encrypted authentication artifacts for agents
class AgentCredential < ApplicationRecord
  include Encryptable

  belongs_to :user

  # Validations
  validates :agent_type, presence: true, inclusion: {
    in: User::AVAILABLE_AGENTS,
    message: "%{value} is not a valid agent type"
  }
  validates :agent_type, uniqueness: { scope: :user_id }
  validates :encrypted_config_data, presence: true

  # Callbacks
  after_create :set_as_user_default
  before_destroy :reassign_user_default

  # Scopes
  scope :for_agent, ->(agent_type) { where(agent_type: agent_type) }
  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Virtual attribute for admin display (shows keys without values)
  def config_keys
    config_data.keys.join(", ")
  rescue StandardError
    "Unable to decrypt"
  end

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

  def set_as_user_default
    user.update!(default_agent_credential: self)
  end

  def reassign_user_default
    return unless user.default_agent_credential_id == id

    fallback = user.agent_credentials.where.not(id: id).order(created_at: :desc).first
    user.update!(default_agent_credential: fallback)
  end

  def encryption_key_setting
    Settings.encryption.credentials_key
  end
end
