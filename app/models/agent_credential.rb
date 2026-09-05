# frozen_string_literal: true

# AgentCredential - Stores encrypted authentication artifacts for agents
class AgentCredential < ApplicationRecord
  include Encryptable
  extend Enumerize

  belongs_to :user
  # Credentials are per (user, company): the same person authenticates a separate
  # agent account per company so vendor spend is billed to the company that
  # incurred it, never pooled across tenants.
  belongs_to :company

  enumerize :status, in: %i[active error], default: :active, predicates: true

  MAX_REFRESH_FAILURES = 3

  # Validations
  validates :agent_type, presence: true, inclusion: {
    in: CompanyMembership::AVAILABLE_AGENTS,
    message: "%{value} is not a valid agent type"
  }
  validates :agent_type, uniqueness: { scope: %i[user_id company_id] }
  validate :owner_is_a_member_of_the_company
  validates :encrypted_config_data, presence: true

  # Scope helper: this company's credentials only.
  scope :for_company, ->(company) { where(company: company) }

  # Callbacks
  after_create :set_as_membership_default
  before_destroy :reassign_membership_default
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
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :refreshable, -> { where(agent_type: REFRESHABLE_AGENT_TYPES) }
  # Credentials whose token expires within `within` (drives the refresh sweep).
  # NULL-expiry credentials (agents whose tokens carry no expiry) are excluded.
  scope :refresh_due, ->(within = 60.minutes) {
    where(status: :active).where.not(expires_at: nil).where(expires_at: ..within.from_now)
  }
  # Credentials no live container currently holds.
  #
  # Launching a session writes the token blocks into the container, so the CLI in
  # there becomes a second holder of the same single-use refresh token — and it
  # rotates that grant whenever it renews. A sweep that refreshes the copy we still
  # hold then replays a token the server has already rotated out, which the token
  # endpoint answers with invalid_grant and, under OAuth reuse detection, can revoke
  # the whole family. Leave those to the container: session cleanup merges the
  # rotated blocks back (see AgentSessionStrategy#persist_refreshed_credentials).
  scope :without_live_session, -> {
    held = TerminalSession.active
                          .where("terminal_sessions.user_id = agent_credentials.user_id")
                          .where("terminal_sessions.company_id = agent_credentials.company_id")
                          .where("terminal_sessions.agent_type = agent_credentials.agent_type")
    where.not(held.arel.exists)
  }

  class PreflightError < StandardError
    attr_reader :credential

    def initialize(credential)
      @credential = credential
      super("Your #{credential.agent_type.titleize} login has expired. Go to profile settings and sign in again.")
    end
  end

  # Virtual attribute for admin display (shows keys without values)
  def config_keys
    config_data.keys.join(", ")
  rescue StandardError
    "Unable to decrypt"
  end

  # Create or replace credential from collected artifacts.
  # config_data is fully replaced (not merged) so re-authentication wipes any
  # stale fields from a previous login/auth method. Settings stored in metadata
  # (env-field values like google_cloud_project) are not auth data, so they
  # survive — only the two bookkeeping keys are refreshed.
  # company_id is part of the identity: the same user holds one credential per
  # company, so a re-auth must replace the right row and never overwrite another
  # company's (separately billed) token.
  #
  # `new_authorization:` marks the call as "the user just logged in again", which
  # additionally drops `default_model`. A model is only meaningful for the auth it
  # was chosen under: authenticating claude_code with a subscription OAuth login
  # after it had been a Bedrock connection left the Bedrock inference-profile ARN
  # in place, and resolve_session_model kept handing every new session a model the
  # new auth cannot invoke ("There's an issue with the selected model … Run /model").
  # Token REFRESH must not pass this — rotating a token is not a new authorization,
  # and wiping the user's pick on every refresh would be its own bug.
  def self.from_artifacts(user_id, company_id, agent_type, artifacts_hash, new_authorization: false)
    credential = find_or_initialize_by(user_id: user_id, company_id: company_id, agent_type: agent_type)
    credential.config_data = artifacts_hash
    credential.status = :active
    credential.refresh_error = nil
    credential.refresh_failure_count = 0
    dropped = %w[collected_at artifact_keys]
    dropped << "default_model" if new_authorization
    preserved = (credential.metadata || {}).except(*dropped)
    credential.metadata = preserved.merge(
      "collected_at" => Time.current,
      "artifact_keys" => artifacts_hash.keys
    )
    credential.save!
    credential
  end

  # The model this credential's sessions default to, with a vendor-retired id
  # mapped to its replacement (see BaseAdapter#migrate_model_id). Every consumer
  # — the profile select, session launch, the generated container config — reads
  # the pin through here, so a default saved before a retirement keeps working
  # instead of 404ing at session start. The stored value is left untouched: the
  # mapping is a rescue for a dead id, not a rewrite of the user's choice.
  def default_model
    stored = metadata&.dig("default_model")
    return nil if stored.blank?

    adapter.migrate_model_id(stored)
  rescue StandardError => e
    Rails.logger.warn("[AgentCredential] default_model lookup failed for #{id}: #{e.message}")
    stored
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
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError, TypeError
    # Fallback: try reading as plain JSON (for existing unencrypted data).
    # InvalidMessage (AES-GCM wrong/rotated key) is rescued too so an un-recrypted
    # row degrades gracefully instead of 500ing during the key-migration window.
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
    result = service.write_to_container(container_id, config_data, workflow_config)
    touch(:last_used_at)
    result
  end

  def mark_refresh_error!(message, permanent: false)
    self.refresh_failure_count = refresh_failure_count.to_i + 1
    self.refresh_error = message.to_s.truncate(500)
    self.status = :error if permanent || refresh_failure_count >= MAX_REFRESH_FAILURES
    save!
  end

  def clear_refresh_error!
    self.status = :active
    self.refresh_error = nil
    self.refresh_failure_count = 0
    save!
  end

  private

  # The default is per membership, so a credential can only ever become the
  # default for the company it belongs to.
  def set_as_membership_default
    membership&.update!(default_agent_credential: self)
  end

  def reassign_membership_default
    m = membership
    return unless m && m.default_agent_credential_id == id

    fallback = AgentCredential.where(user_id: user_id, company_id: company_id)
                              .where.not(id: id)
                              .order(created_at: :desc)
                              .first
    m.update!(default_agent_credential: fallback)
  end

  def membership
    @membership ||= CompanyMembership.find_by(user_id: user_id, company_id: company_id)
  end

  # A credential only makes sense while its owner belongs to that company;
  # otherwise it would bill a company the user has no relationship with.
  def owner_is_a_member_of_the_company
    return if user_id.blank? || company_id.blank?
    return if CompanyMembership.exists?(user_id: user_id, company_id: company_id)

    errors.add(:company, "must be one the user is a member of")
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
