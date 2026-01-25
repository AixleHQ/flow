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

  before_validation :set_onboarding_completed_at, if: :onboarding_completed?

  # Scopes
  scope :for_company, ->(company) { where(company: company) }

  # Helper methods
  def onboarding_completed?
    return true if super_admin?

    position.present? &&
      preferred_agent_language.present? &&
      configured_agents.present? &&
      configured_agents.any?
  end

  # All projects user has access to (owned + collaborated)
  def projects
    Project.where(id: owned_projects.select(:id))
           .or(Project.where(id: collaborated_projects.select(:id)))
  end

  # Add agent to configured_agents array
  def add_configured_agent(agent_type)
    return false unless AVAILABLE_AGENTS.include?(agent_type)
    return true if configured_agents&.include?(agent_type)

    self.configured_agents ||= []
    self.configured_agents << agent_type
    save
  end

  # Remove agent from configured_agents array
  def remove_configured_agent(agent_type)
    return false if configured_agents.blank?

    self.configured_agents = configured_agents.reject { |a| a == agent_type }
    save
  end

  private

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
