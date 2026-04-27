# frozen_string_literal: true

class User < ApplicationRecord
  extend Enumerize

  # State machine
  include UserStateMachine

  has_secure_password validations: false

  # Virtual attribute for invitation flow
  attr_accessor :inviter

  # Constants
  AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
  POSITIONS = %w[qa pm_po_ba dev designer cto].freeze
  AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli].freeze

  # Enumerize for roles and positions (not state machines)
  enumerize :role, in: %i[employee admin super_admin], default: :employee, predicates: true, scope: true
  enumerize :position, in: POSITIONS, predicates: true

  # Associations
  belongs_to :company, optional: true
  belongs_to :invited_by, class_name: "User", optional: true
  has_many :invited_users, class_name: "User", foreign_key: :invited_by_id, dependent: :nullify, inverse_of: :invited_by
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner
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

  def agent_models_by_type
    agent_credentials.each_with_object({}) do |cred, hash|
      cache_key = "agent_models/#{cred.agent_type}"
      models = Rails.cache.read(cache_key)

      if models.nil?
        adapter = AgentCredentialsService.for(cred.agent_type).adapter
        result = adapter.fetch_available_models_with_source(cred.config_data, credential: cred)
        models = result[:models] || []
        Rails.cache.write(cache_key, models, expires_in: 1.day) if models.any?
      end

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
      has_configured_agents?
  end

  # Setter for invitation flow - sets invited_by and invited_at
  def inviter=(user)
    return unless user.present?

    self.invited_by = user
    self.invited_at = Time.current
  end

  private

  def set_onboarding_completed_at
    self.onboarding_completed_at = Time.current
  end

  # Validation: email domain must match company domain
  def email_domain_matches_company
    return if company.blank? || email.blank?
    return if super_admin?

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
