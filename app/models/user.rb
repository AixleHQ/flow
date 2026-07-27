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

  # Constants
  AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
  POSITIONS = %w[qa pm_po_ba dev designer cto].freeze
  AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli].freeze

  # Enumerize for positions (roles live on CompanyMembership; super_admin is a boolean)
  enumerize :position, in: POSITIONS, predicates: true

  # Associations
  has_many :company_memberships, dependent: :destroy
  has_many :companies, through: :company_memberships
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :restrict_with_error, inverse_of: :owner
  has_many :terminal_sessions, dependent: :destroy
  has_many :agent_credentials, dependent: :destroy
  has_one :namespace_resource_quota, as: :scope, dependent: :destroy
  belongs_to :default_agent_credential, class_name: "AgentCredential", optional: true

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, if: :password_digest_changed?, allow_blank: true
  validates :preferred_agent_language, inclusion: { in: AGENT_LANGUAGES }, allow_nil: true
  validate :selected_agents_valid
  validate :default_agent_credential_belongs_to_user

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

  # Helper: check if onboarding is completed (based on state machine)
  def onboarding_completed?
    return true if super_admin?

    onboarding_state == "completed"
  end

  # List of configured agent types (derived from credentials)
  def configured_agents
    agent_credentials.pluck(:agent_type)
  end

  def default_agent_runtime
    default_agent_credential&.agent_type
  end

  # All projects user has access to (owned + collaborated)
  def projects
    Project.where(id: owned_projects.select(:id))
           .or(Project.where(id: collaborated_projects.select(:id)))
  end

  def has_configured_agents?
    agent_credentials.exists?
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
    remove_instance_variable(:@viewer_everywhere) if defined?(@viewer_everywhere)
    self
  end

  def reload(...)
    reload_active_memberships
    super
  end

  # A pure external observer: every active membership is a viewer membership.
  # Used by onboarding guards — such users never connect/run an agent.
  # NOTE: false for zero memberships — callers gating writes must fail closed
  # on `active_memberships.none?` separately (see Api::V1::ApplicationPolicy).
  def viewer_everywhere?
    return @viewer_everywhere if defined?(@viewer_everywhere)

    @viewer_everywhere = active_memberships.any? && active_memberships.all?(&:viewer?)
  end

  # Viewers-everywhere never connect/run an agent, so onboarding must not require one.
  def onboarding_requires_agent?
    !viewer_everywhere?
  end

  def can_advance_to_authenticated?
    onboarding_requires_agent? ? has_configured_agents? : true
  end

  def agent_models_by_type
    agent_credentials.each_with_object({}) do |cred, hash|
      models = fetch_or_cache_agent_models(cred)

      hash[cred.agent_type] = models.map do |m|
        { model_id: m[:model_id] || m["model_id"], display_name: m[:display_name] || m["display_name"], description: m[:description] || m["description"] }
      end
    end
  end

  def agent_models_for_props
    agent_models_by_type.map do |agent_type, models|
      { agent_type: agent_type, models: models }
    end
  end

  # A user who finished onboarding but now needs an agent credential and has
  # none. Reachable because onboarding's agent step is skipped for
  # viewers-everywhere (onboarding_requires_agent?) and onboarding never
  # re-runs: a viewer who is later given an employee/admin membership may now
  # act, but has no agent connected and nothing in the flow says so — they just
  # find empty agent pickers.
  def needs_agent_setup?
    return false if super_admin?
    return false if active_memberships.none?

    # `agent_credentials.none?` rather than has_configured_agents?: this runs on
    # every request via CurrentUserResource, which already serialises
    # `many :agent_credentials`, so reading the loaded association costs nothing.
    # (Unloaded, Relation#none? still issues an exists?, not a full load.)
    onboarding_completed? && onboarding_requires_agent? && agent_credentials.none?
  end

  # Called right after an invitation is accepted: if the new membership means the
  # user now needs an agent they never connected, send them back through the
  # agent steps instead of leaving them with empty pickers. Returns true when
  # onboarding was re-opened, so callers can redirect there.
  def reopen_onboarding_if_setup_needed!
    # The membership flipped to active moments ago; drop the memoized list so
    # needs_agent_setup? sees it.
    reload_active_memberships
    return false unless needs_agent_setup?

    aasm(:onboarding_state).fire(:reopen)
    save!
    true
  end

  def can_complete_onboarding?
    position.present? &&
      preferred_agent_language.present? &&
      (viewer_everywhere? || has_configured_agents?)
  end

  private

  # Fetch the model list for a credential, caching per-credential (not globally —
  # the old key collided across users, so one user's fallback poisoned everyone).
  # API-sourced lists are cached for a day; fallback lists only briefly, so a
  # transient API failure or an expired token doesn't pin a stale list for 24h.
  # The cache is also busted whenever the credential's auth data changes
  # (re-auth / refreshed token) — see AgentCredential#invalidate_models_cache.
  def fetch_or_cache_agent_models(cred)
    cache_key = cred.models_cache_key
    cached = Rails.cache.read(cache_key)
    return cached if cached

    adapter = AgentCredentialsService.for(cred.agent_type).adapter
    result = adapter.fetch_available_models_with_source(cred.config_data, credential: cred)
    models = result[:models] || []

    if models.any?
      ttl = result[:source] == :api ? 1.day : 1.hour
      Rails.cache.write(cache_key, models, expires_in: ttl)
    end

    models
  end

  def set_onboarding_completed_at
    self.onboarding_completed_at = Time.current
  end

  def selected_agents_valid
    return if selected_agents.blank?

    invalid_agents = selected_agents - AVAILABLE_AGENTS
    return if invalid_agents.empty?

    errors.add(:selected_agents, "contains invalid agents: #{invalid_agents.join(', ')}")
  end

  def default_agent_credential_belongs_to_user
    return if default_agent_credential_id.blank?
    return if agent_credentials.exists?(id: default_agent_credential_id)

    errors.add(:default_agent_credential_id, "must belong to this user")
  end
end
