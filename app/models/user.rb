# frozen_string_literal: true

class User < ApplicationRecord
  extend Enumerize

  # State machine
  include UserStateMachine

  has_secure_password validations: false

  # ── Personal MCP token ──
  # One opt-in token per user for the global MCP server (MCPController):
  # grants exactly the user's own access level, enforced per tool through the
  # same Pundit policies the UI uses. Digest-only storage; plaintext is
  # returned once from regenerate_mcp_token! and never persisted.
  MCP_TOKEN_PREFIX = "amcp_"

  def self.find_by_mcp_token(token)
    return nil unless token.is_a?(String) && token.start_with?(MCP_TOKEN_PREFIX)

    find_by(mcp_token_digest: Digest::SHA256.hexdigest(token))
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

  # Associations
  has_many :company_memberships, dependent: :destroy
  has_many :companies, through: :company_memberships
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :project_favorites, dependent: :destroy
  has_many :favorite_projects, through: :project_favorites, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :restrict_with_error, inverse_of: :owner
  has_many :terminal_sessions, dependent: :destroy
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
  has_one :namespace_resource_quota, as: :scope, dependent: :destroy

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
end
