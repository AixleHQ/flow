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
  # Bust the cached model list whenever the stored auth data changes (re-auth or a
  # refreshed token) or the record is removed, so the profile select never serves
  # models fetched with a stale token. See User#fetch_or_cache_agent_models.
  after_save :invalidate_models_cache, if: :saved_change_to_encrypted_config_data?
  after_destroy :invalidate_models_cache
  # Keep expires_at in sync with the token material in config_data so the `.active`
  # scope and the proactive token-refresh sweep have a real expiry to read. Only
  # recompute when the encrypted blob actually changes — a bare touch(:last_used_at)
  # or metadata-only save leaves the token untouched. See #sync_expires_at.
  before_save :sync_expires_at, if: :will_save_change_to_encrypted_config_data?

  broadcasts_to :user

  # Agent types whose credentials carry a refreshable OAuth token.
  REFRESHABLE_AGENT_TYPES = %w[claude_code codex cursor_cli].freeze

  # Scopes
  scope :for_agent, ->(agent_type) { where(agent_type: agent_type) }
  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :refreshable, -> { where(agent_type: REFRESHABLE_AGENT_TYPES) }
  # Credentials whose token expires within `within` (drives the refresh sweep).
  # NULL-expiry credentials (agents whose tokens carry no expiry) are excluded.
  scope :refresh_due, ->(within = 15.minutes) {
    where.not(expires_at: nil).where(expires_at: ..within.from_now)
  }

  # Virtual attribute for admin display (shows keys without values)
  def config_keys
    config_data.keys.join(", ")
  rescue StandardError
    "Unable to decrypt"
  end

  # Create or replace credential from collected artifacts.
  # config_data is fully replaced (not merged) so re-authentication wipes any
  # stale fields from a previous login/auth method. Settings stored in metadata
  # (the user's default_model, env-field values like google_cloud_project) are
  # not auth data, so they survive re-auth — only the two bookkeeping keys are
  # refreshed.
  def self.from_artifacts(user_id, agent_type, artifacts_hash)
    credential = find_or_initialize_by(user_id: user_id, agent_type: agent_type)
    credential.config_data = artifacts_hash
    preserved = (credential.metadata || {}).except("collected_at", "artifact_keys")
    credential.metadata = preserved.merge(
      "collected_at" => Time.current,
      "artifact_keys" => artifacts_hash.keys
    )
    credential.save!
    credential
  end

  # Cache key for this credential's fetched model list (per-credential, not global).
  def models_cache_key
    "agent_models/#{agent_type}/#{id}"
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

  def invalidate_models_cache
    Rails.cache.delete(models_cache_key)
  end

  # Derive expires_at from the adapter's soonest token expiry (epoch ms → Time).
  # nil when the agent's tokens carry no expiry (e.g. codex/cursor today), which
  # keeps the credential always-active in `.active` (its expiry is unknown, not past).
  def sync_expires_at
    ms = adapter.token_expires_at(config_data)
    self.expires_at = ms ? Time.zone.at(ms / 1000.0) : nil
  rescue StandardError => e
    Rails.logger.warn("[AgentCredential] sync_expires_at failed for #{id}: #{e.message}")
    self.expires_at = nil
  end

  def encryption_key_setting
    Settings.encryption.credentials_key
  end
end
