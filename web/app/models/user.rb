# frozen_string_literal: true

class User < ApplicationRecord
  extend Enumerize

  # State machine
  include UserStateMachine

  has_secure_password validations: false

  # Constants
  AGENT_LANGUAGES = %w[en ru es zh fr de ja pt it pl uk].freeze
  POSITIONS = %w[qa pm_po_ba dev designer cto].freeze
  AVAILABLE_AGENTS = %w[claude_code cursor_cli codex gemini_cli].freeze

  # Enumerize for roles and positions (not state machines)
  enumerize :role, in: %i[employee admin super_admin], default: :employee, predicates: true, scope: true
  enumerize :position, in: POSITIONS, predicates: true

  # Associations
  belongs_to :company, optional: true
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner
  has_many :terminal_sessions, dependent: :destroy
  has_many :agent_credentials, dependent: :destroy

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

  # Scopes
  scope :for_company, ->(company) { where(company: company) }

  # Helper: check if onboarding is completed (based on state machine)
  def onboarding_completed?
    return true if super_admin?

    onboarding_state == "completed"
  end

  # List of configured agent types (derived from credentials)
  def configured_agents
    agent_credentials.pluck(:agent_type)
  end

  # All projects user has access to (owned + collaborated)
  def projects
    Project.where(id: owned_projects.select(:id))
           .or(Project.where(id: collaborated_projects.select(:id)))
  end

  # Guard for state machine: check if user can complete onboarding (all requirements met)
  def can_complete_onboarding?
    position.present? &&
      preferred_agent_language.present? &&
      agent_credentials.exists?
  end

  private

  # Callback for state machine: set timestamp when onboarding completes
  def set_onboarding_completed_at
    self.onboarding_completed_at = Time.current
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

  def set_onboarding_completed_at
    self.onboarding_completed_at = Time.current
  end
end
