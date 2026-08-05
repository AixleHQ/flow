# frozen_string_literal: true

class Integration < ApplicationRecord
  include Encryptable
  extend Enumerize

  enumerize :provider, in: %i[github gitlab linear coder slack], predicates: true
  enumerize :status, in: %i[active inactive error], default: :inactive, predicates: true, scope: true

  belongs_to :company
  belongs_to :project, optional: true
  belongs_to :connected_by, class_name: "User"
  has_many :repositories, dependent: :destroy
  has_many :integration_data, class_name: "IntegrationData", dependent: :delete_all

  validates :name, presence: true
  validates :provider, presence: true
  validate :project_belongs_to_same_company, if: -> { project_id.present? }

  scope :for_company, ->(company) { where(company: company) }
  scope :company_wide, -> { where(project_id: nil) }
  scope :for_project, ->(project) { where(project_id: project.id) }
  scope :active, -> { where(status: "active") }
  scope :visible_for_project, ->(project) {
    where(company_id: project.company_id, project_id: nil).or(where(project_id: project.id))
  }

  # personal_access_token lives in encrypted credentials — no DB lookup possible.
  def self.find_or_build_gitlab_for_token(company:, connected_by:, project:)
    company.integrations.build(provider: :gitlab, connected_by: connected_by, project: project)
  end

  # installation_id lives in encrypted credentials — match in Ruby after scope filter.
  def self.find_or_build_github_for_installation(company:, connected_by:, project:, installation_id:)
    id_str = installation_id.to_s
    scoped =
      if project
        company.integrations.where(project_id: project.id, provider: :github)
      else
        company.integrations.company_wide.where(provider: :github)
      end

    scoped.find { |i| i.installation_id == id_str } ||
      company.integrations.build(provider: :github, connected_by: connected_by, project: project)
  end

  def credentials_data=(hash)
    self.credentials = encryptor.encrypt_and_sign(hash.to_json)
  end

  def credentials_data
    return {} if credentials.blank?

    JSON.parse(encryptor.decrypt_and_verify(credentials))
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage,
         JSON::ParserError
    {}
  end

  def installation_id
    credentials_data["installation_id"]
  end

  # GitHub account (org or user) the App is installed on. Recorded at connect
  # time by Github::IntegrationService; blank on integrations connected before
  # that, and on installations that never verified.
  def github_account_login
    settings&.dig("account_login")
  end

  # ----- Coder accessors -----

  def coder_url
    credentials_data["coder_url"]
  end

  def coder_user_id
    credentials_data["user_id"]
  end

  def coder_default_template
    settings&.dig("default_template")
  end

  def coder_machine_prefix
    settings&.dig("machine_prefix")
  end

  def coder_lock_ttl_minutes
    settings&.dig("lock_ttl_minutes")&.to_i
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name provider status created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[company project connected_by]
  end

  private

  def project_belongs_to_same_company
    return if project.blank? || company.blank?
    return if project.company_id == company_id

    errors.add(:project, "must belong to the same company")
  end

  def encryption_key_setting
    Settings.encryption.integrations_key
  end
end
