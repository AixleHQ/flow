# frozen_string_literal: true

# One OAuth token set for a given owner identity against one authorization server.
# owner answers "whose identity does the agent act as": Company/Project = shared
# service identity (today's config_item semantics); User = per-user identity.
class OauthCredential < ApplicationRecord
  include Encryptable
  extend Enumerize

  belongs_to :owner, polymorphic: true
  belongs_to :oauth_client
  belongs_to :mcp_server, optional: true

  enumerize :status, in: %i[pending active error revoked],
                     default: :pending, predicates: true, scope: true

  validates :provider, presence: true
  validates :owner_type, inclusion: { in: %w[User Company Project] }

  # Only non-secret account/identity fields from a token response are persisted to
  # the PLAINTEXT metadata column — never id_token or other bearer-capable material
  # (a {access,refresh}_token denylist would still leak an OIDC id_token in cleartext).
  SAFE_METADATA_KEYS = %w[account user organization token_uuid].freeze

  # --- Scopes ---
  scope :for_owner,      ->(owner) { where(owner: owner) }
  scope :for_mcp_server, ->(server) { where(mcp_server_id: server.id) }
  # Sweep scope (Phase 2 consumes this; index [:status, :expires_at] backs it).
  scope :refresh_due, ->(within = 15.minutes) {
    with_status(:active).where.not(encrypted_refresh_token: nil).where(expires_at: ..within.from_now)
  }

  # --- Encrypted accessors (Encryptable) ---
  def access_token=(val)
    self.encrypted_access_token = val.present? ? encryptor.encrypt_and_sign(val) : nil
  end

  def access_token
    decrypt(encrypted_access_token)
  end

  def refresh_token=(val)
    self.encrypted_refresh_token = val.present? ? encryptor.encrypt_and_sign(val) : nil
  end

  def refresh_token
    decrypt(encrypted_refresh_token)
  end

  # --- Methods the TokenService and callback rely on (pinned; see §9) ---

  # True when the access token is missing or within `skew` of expiry.
  def expired?(skew = 10.minutes)
    return true  if access_token.blank?
    return false if expires_at.nil?          # tokens with no expiry never proactively refresh

    expires_at < skew.from_now
  end

  def refreshable?
    refresh_token.present? && oauth_client.present?
  end

  # Callback (FLOW_ENGINE) upserts here after a code exchange. Idempotent on the
  # unique index; always lands status: :active. token_response keys are strings.
  def self.upsert_from_token!(owner:, oauth_client:, provider:, token_response:, mcp_server: nil)
    cred = find_or_initialize_by(
      owner: owner, oauth_client: oauth_client, provider: provider, mcp_server_id: mcp_server&.id
    )
    cred.apply_token_response!(token_response)
    cred
  end

  # Persist a token/refresh response (from exchange OR refresh). Never wipes an
  # existing refresh_token when the response omits one (rotation: providers may
  # return only a new access token). Sets status: :active, clears refresh_error.
  def apply_token_response!(resp)
    self.access_token  = resp["access_token"]
    self.refresh_token = resp["refresh_token"] if resp["refresh_token"].present?
    self.token_type    = resp["token_type"].presence || "Bearer"
    self.scopes        = resp["scope"] if resp.key?("scope")
    self.expires_at    = resp["expires_in"].present? ? Time.current + resp["expires_in"].to_i.seconds : nil
    self.metadata      = (metadata || {}).merge(resp.slice(*SAFE_METADATA_KEYS))
    self.status        = :active
    self.refresh_error = nil
    self.last_refreshed_at = Time.current
    save!
  end

  # Mark a failed refresh; N-consecutive-failure escalation is Phase 2.
  def mark_refresh_error!(message)
    update!(status: :error, refresh_error: message.to_s.truncate(500))
  end

  private

  def decrypt(cipher)
    return nil if cipher.blank?

    encryptor.decrypt_and_verify(cipher)
  # AES-GCM (this app's cipher) raises InvalidMessage on wrong-key/tampered
  # ciphertext; InvalidSignature is the CBC/HMAC-era name. Rescue both so a
  # rotated or corrupt key decrypts to nil instead of crashing (mirrors
  # Integration#credentials_data).
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def encryption_key_setting
    Settings.encryption.oauth_key
  end
end
