# frozen_string_literal: true

class User < ApplicationRecord
  extend Enumerize
  include Encryptable

  encryption_key :credentials_key
  encrypted_column :encrypted_totp_secret

  DELETED_DISPLAY_NAME = "Deleted user"

  # State machine
  include UserStateMachine

  has_secure_password validations: false

  # A new password ends every browser signed in with the old one.
  after_update_commit :end_sessions_after_password_change, if: :saved_change_to_password_digest?

  # ── Personal MCP token ──
  # One opt-in token per user for the global MCP server (MCPController):
  # grants exactly the user's own access level, enforced per tool through the
  # same Pundit policies the UI uses. Digest-only storage; plaintext is
  # returned once from regenerate_mcp_token! and never persisted.
  MCP_TOKEN_PREFIX = "amcp_"

  # A stable, opaque handle for WebAuthn's user id. Not the email (it changes,
  # and a credential bound to it would outlive the address) and not the raw id
  # (which leaks a record count to every authenticator the person uses).
  def webauthn_handle
    Digest::SHA256.hexdigest("webauthn-user:#{id}")
  end

  # ── TOTP (step-up only) ──
  # The secret is encrypted at rest under the same key as every other credential
  # this app holds. `totp_confirmed_at` is what makes it live: a secret that was
  # generated but never verified must not start locking anyone out.
  def totp_secret=(value)
    self.encrypted_totp_secret = encrypt_secret(value.presence, column: :encrypted_totp_secret)
  end

  def totp_secret
    return nil if encrypted_totp_secret.blank?

    decrypt_secret(encrypted_totp_secret, column: :encrypted_totp_secret)
  end

  def totp_enabled?
    encrypted_totp_secret.present? && totp_confirmed_at.present?
  end

  def totp_provisioning_uri(issuer:)
    return nil if totp_secret.blank?

    ROTP::TOTP.new(totp_secret, issuer: issuer).provisioning_uri(email)
  end

  def verify_totp(code, drift: 30)
    return false if totp_secret.blank? || code.blank?

    # `drift_behind`/`drift_ahead` rather than a bare match: a phone clock is
    # never exactly ours, and rejecting a correct code over half a second of skew
    # is how a second factor gets switched off by its users.
    ROTP::TOTP.new(totp_secret).verify(code.to_s.strip, drift_behind: drift, drift_ahead: drift).present?
  end

  def link_password_identity
    return if password_digest.blank?

    Auth::LocalCredential.link!(self)
  end

  def self.find_by_mcp_token(token)
    return nil unless token.is_a?(String) && token.start_with?(MCP_TOKEN_PREFIX)

    authenticatable.find_by(mcp_token_digest: Digest::SHA256.hexdigest(token))
  end

  def regenerate_mcp_token!
    token = "#{MCP_TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    update!(mcp_token_digest: Digest::SHA256.hexdigest(token), mcp_token_last_used_at: nil)
    token
  end

  def disable_mcp_token!
    update!(mcp_token_digest: nil, mcp_token_last_used_at: nil)
  end

  def mcp_enabled?
    mcp_token_digest.present?
  end

  # "Last used" is shown to the minute at most; writing it on every MCP call
  # made each tool call a row update on users.
  MCP_TOKEN_USE_GRANULARITY = 5.minutes

  def note_mcp_token_use!(now = Time.current)
    return if mcp_token_last_used_at && mcp_token_last_used_at > now - MCP_TOKEN_USE_GRANULARITY

    update_columns(mcp_token_last_used_at: now)
  end

  # Associations
  has_many :company_memberships, dependent: :destroy
  has_many :user_sessions, dependent: :delete_all
  # Per-user OAuth connections: the account's, gone with it (and never refreshed after).
  has_many :oauth_credentials, as: :owner, dependent: :destroy
  has_many :companies, through: :company_memberships
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :project_favorites, dependent: :destroy
  has_many :favorite_projects, through: :project_favorites, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :restrict_with_error, inverse_of: :owner
  # The company's record of work done and spent: kept, owned by nobody, when the
  # user is permanently deleted (Users::PermanentDeletionService).
  has_many :terminal_sessions, dependent: :nullify
  # Personal saved board views — destroyed with the user on permanent deletion.
  has_many :board_view_presets, dependent: :destroy
  # Credentials belong to a (user, company) pair — the default for a company
  # lives on that CompanyMembership, not here.
  #
  # This association exists for lifecycle only (dependent: :destroy). Never read it to
  # PICK a credential: `user.agent_credentials.find_by(agent_type:)` is a coin flip for
  # a multi-company user, and losing that flip hands a container another tenant's tokens
  # and bills that tenant. Read through the company instead —
  # CompanyMembership#credentials_scope, SessionCompany.agent_credentials_for(session),
  # or CloudAuth::CredentialLookup.
  has_many :agent_credentials, dependent: :destroy

  # Every way this person can prove who they are (AD-3), and every live login
  # session they hold (AD-6). "Does this user have credentials?" is
  # `user_identities.any?` — never a password_digest check.
  has_many :user_identities, dependent: :destroy
  # A passkey belongs to the person, not to any company (AD-18).
  has_many :webauthn_credentials, dependent: :destroy
  has_many :magic_link_tokens, dependent: :destroy

  # Setting a password IS acquiring a credential, so the identity row appears
  # with it — whether the password came from the login form, an invitation
  # signup, the admin panel, or seeds. Without this, "has credentials" and
  # "has identities" disagree for every user whose password was written
  # directly, and the policy guard (which reads identities) misjudges them.
  after_save :link_password_identity, if: :saved_change_to_password_digest?

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, if: :password_digest_changed?, allow_blank: true

  broadcasts_to ->(user) { user }, on: :update

  # Scopes
  # Members of a company, soft-deleted accounts excluded: a deleted user must not
  # surface in member lists, pickers or session scopes. Membership STATE is left
  # to the caller (`.merge(CompanyMembership.active)`), since the members screen
  # deliberately shows invited/suspended rows too.
  scope :for_company, ->(company) {
    joins(:company_memberships).not_deleted.where(company_memberships: { company_id: company.id })
  }
  # Soft-delete scopes. NOTE: we deliberately do NOT name the positive scope
  # `active` (as Asset/Workflow/Tool do) because AASM already generates an
  # `active` scope for the :active account state, which authentication relies on
  # (AuthConcern#current_user). `not_deleted` keeps the two concepts orthogonal.
  scope :not_deleted, -> { where(deleted_at: nil) }
  # Who may authenticate at all. Every way in — the web session, the API, the
  # personal MCP token, ActionCable, the container gates — uses this one scope,
  # so a suspended or deleted account is shut out everywhere at once.
  scope :authenticatable, -> { active.not_deleted }

  # The record-level twin of `authenticatable`, for a user already loaded.
  def authenticatable?
    active? && !deleted?
  end

  # A cookie from before database sessions carries only the user id and has no
  # session row to revoke, so it is taken only until the user's sessions are first
  # ended everywhere (UserSession.revoke_all_for!).
  def accepts_sessionless_cookie? = sessions_revoked_at.nil?
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Soft delete — mirrors the deleted_at pattern used by Asset/Workflow/Tool.
  # Deleting a user hard-deletes nothing: board activities and other historical
  # records referencing the user are preserved, and the FK on
  # board_activities.actor_id is never violated.
  #
  # Memberships are deliberately left ALONE rather than revoked. Two reasons:
  # revoking would make restore! lossy (it cannot know which companies to
  # rejoin, or at which role), and revoking the sole admin of a company would
  # either trip the last-admin guard or force us to bypass validations. Instead
  # `deleted_at` is the single source of truth and is filtered at every read:
  # authentication (AuthConcern#current_user, UserSignInForm, the omniauth
  # guard), Company#users, and User.for_company. A deleted user therefore cannot
  # sign in and appears nowhere, while restore! brings back exactly what existed.
  def soft_delete!
    update!(deleted_at: Time.current)
    revoke_live_access!
  end

  # What outlives a sign-in: its browser sessions, the personal MCP token and open
  # cable connections. Called when the account stops being authenticatable.
  def revoke_live_access!
    update_columns(mcp_token_digest: nil, mcp_token_last_used_at: nil) if mcp_token_digest.present?
    UserSession.revoke_all_for!(self)
    ActionCable.server.remote_connections.where(current_user: self).disconnect
  rescue StandardError => e
    Rails.logger.warn("[User] Failed to revoke live access for user #{id}: #{e.message}")
  end

  def end_sessions_after_password_change
    UserSession.revoke_all_for!(self)
  end

  def restore!
    raise ActiveRecord::RecordNotFound, "User is not deleted" unless deleted?

    update!(deleted_at: nil)
  end

  def deleted?
    deleted_at.present?
  end

  # Ransack configuration
  def self.ransackable_attributes(_auth_object = nil)
    # `role` is gone from users — the per-company role lives on CompanyMembership.
    %w[email name state deleted_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  # All projects user has access to (owned + collaborated)
  def projects
    Project.where(id: owned_projects.select(:id))
           .or(Project.where(id: collaborated_projects.select(:id)))
  end

  # Active memberships, loaded once per User instance. Every company-scoped
  # request goes through this: AuthConcern#current_membership, BaseContext,
  # project permissions, Project#accessible_by? and the current-user props.
  # No :company here — see #active_memberships_with_company.
  def active_memberships
    @active_memberships ||= company_memberships.active.to_a
  end

  # The same memoized list with :company preloaded, done on FIRST DEREFERENCE
  # rather than up front. Bullet gates this from both sides: eager-loading
  # unconditionally trips "AVOID eager loading" on the many requests that only
  # need role predicates, while lazily loading :company off an already-loaded
  # collection trips "USE eager loading". Preloading on demand satisfies both —
  # zero companies queries when no company is dereferenced, exactly one when any
  # is. Callers that read `membership.company` MUST come through here.
  def active_memberships_with_company
    unless @active_memberships_company_preloaded
      list = active_memberships
      ActiveRecord::Associations::Preloader.new(records: list, associations: :company).call if list.any?
      @active_memberships_company_preloaded = true
    end

    active_memberships
  end

  # Drop the memoized list when a membership changes mid-request (leaving a
  # company, accepting an invitation) — cheaper than a full record reload, and
  # the request must not keep serving the pre-change membership set.
  def reload_active_memberships
    @active_memberships = nil
    @active_memberships_company_preloaded = false
    self
  end

  def reload(...)
    reload_active_memberships
    super
  end

  # Encryptable calls the first from a private context; the second is an
  # after_save callback. Neither is anyone else's business.
  private :link_password_identity
end
