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

  # Virtual attribute for invitation flow
  attr_accessor :inviter

  # Constants
  AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
  POSITIONS = %w[qa pm_po_ba dev designer cto].freeze
  AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli].freeze

  # Enumerize for roles and positions (not state machines)
  enumerize :role, in: %i[employee admin super_admin viewer], default: :employee, predicates: true, scope: true
  enumerize :position, in: POSITIONS, predicates: true

  # Associations
  belongs_to :company, optional: true
  belongs_to :invited_by, class_name: "User", optional: true
  has_many :invited_users, class_name: "User", foreign_key: :invited_by_id, dependent: :nullify, inverse_of: :invited_by
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
  validates :company_id, presence: true, unless: :super_admin?
  validate :super_admin_company_validation
  validate :selected_agents_valid
  validate :email_domain_matches_company, on: :create
  validate :cannot_demote_last_admin, on: :update
  validate :default_agent_credential_belongs_to_user

  broadcasts_to ->(user) { user }, on: :update

  # Scopes
  scope :for_company, ->(company) { where(company: company) }
  scope :invited, -> { where.not(invited_by_id: nil) }

  # Ransack configuration
  def self.ransackable_attributes(_auth_object = nil)
    %w[email name role state]
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

  # A "client" (external observer) account: read-only everywhere, cannot run/mutate.
  def read_only?
    viewer?
  end

  # Clients never connect/run an agent, so onboarding must not require one.
  def onboarding_requires_agent?
    !read_only?
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

  def can_complete_onboarding?
    position.present? &&
      preferred_agent_language.present? &&
      (read_only? || has_configured_agents?)
  end

  # Setter for invitation flow - sets invited_by and invited_at
  def inviter=(user)
    return unless user.present?

    self.invited_by = user
    self.invited_at = Time.current
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

  # Validation: email domain must match company domain
  def email_domain_matches_company
    return if company.blank? || email.blank?
    return if super_admin?
    return if read_only? # external clients have their own email domain

    domain = email.split("@").last
    return if domain == company.email_domain

    errors.add(:email, "domain must match company domain (#{company.email_domain})")
  end

  def selected_agents_valid
    return if selected_agents.blank?

    invalid_agents = selected_agents - AVAILABLE_AGENTS
    return if invalid_agents.empty?

    errors.add(:selected_agents, "contains invalid agents: #{invalid_agents.join(', ')}")
  end

  def super_admin_company_validation
    if super_admin?
      errors.add(:company_id, "must be nil for super_admin users") if company_id.present?
    else
      errors.add(:company_id, "must be present for non-super_admin users") if company_id.nil?
    end
  end

  def default_agent_credential_belongs_to_user
    return if default_agent_credential_id.blank?
    return if agent_credentials.exists?(id: default_agent_credential_id)

    errors.add(:default_agent_credential_id, "must belong to this user")
  end

  def cannot_demote_last_admin
    return unless company.present?
    return unless role_changed?
    return unless role_was == "admin" && role != "admin"

    admin_count = company.users.where(role: "admin").count
    # If we're the last admin and trying to demote, block it
    if admin_count <= 1
      errors.add(:role, "Cannot demote the last admin")
    end
  end
end
