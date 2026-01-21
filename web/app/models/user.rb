# frozen_string_literal: true

class User < ApplicationRecord
  extend Enumerize

  AVAILABLE_AGENTS = AgentCredential::AGENT_TYPES

  has_secure_password

  enumerize :status, in: %i[active suspended archived], default: :active, predicates: true, scope: true

  # Associations
  belongs_to :company
  has_many :project_collaborators, dependent: :destroy
  has_many :collaborated_projects, through: :project_collaborators, source: :project
  has_many :owned_projects, class_name: "Project", foreign_key: :owner_id, dependent: :nullify, inverse_of: :owner
  has_many :agent_credentials, dependent: :destroy

  # Validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Scopes
  scope :for_company, ->(company) { where(company: company) }
  scope :onboarding_completed, -> { where.not(onboarding_completed_at: nil) }
  scope :onboarding_pending, -> { where(onboarding_completed_at: nil) }

  # All projects user has access to (owned + collaborated)
  def projects
    Project.where(id: owned_projects.select(:id))
           .or(Project.where(id: collaborated_projects.select(:id)))
  end

  # Onboarding
  def onboarding_completed?
    onboarding_completed_at.present?
  end

  def complete_onboarding!(agents)
    transaction do
      update!(
        selected_agents: agents,
        onboarding_completed_at: Time.current
      )

      # Create pending credentials for selected agents
      agents.each do |agent_type|
        agent_credentials.find_or_create_by!(agent_type: agent_type)
      end
    end
  end

  # Agent helpers
  def configured_agents
    agent_credentials.configured.pluck(:agent_type)
  end

  def pending_agents
    agent_credentials.pending.pluck(:agent_type)
  end

  def agent_credential_for(agent_type)
    agent_credentials.find_by(agent_type: agent_type)
  end

  def all_agents_configured?
    return false if selected_agents.blank?

    selected_agents.all? { |agent| agent_credential_for(agent)&.configured? }
  end
end
