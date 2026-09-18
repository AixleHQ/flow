# frozen_string_literal: true

class Integration < ApplicationRecord
  include Encryptable
  extend Enumerize

  enumerize :provider, in: %i[github gitlab linear coder slack azure_devops youtrack], predicates: true
  enumerize :status, in: %i[active inactive error], default: :inactive, predicates: true, scope: true

  belongs_to :company
  belongs_to :project, optional: true
  belongs_to :connected_by, class_name: "User", optional: true
  # Service-principal mode only: the approved company→organization binding this
  # project connection draws its credentials from. Null in PAT mode.
  belongs_to :azure_devops_installation, optional: true
  has_many :repositories, dependent: :destroy
  has_many :integration_data, class_name: "IntegrationData", dependent: :delete_all
  has_many :azure_devops_operations, dependent: :delete_all
  has_many :azure_devops_subscriptions, dependent: :destroy
  has_many :trigger_bindings, dependent: :nullify

  before_destroy :destroy_youtrack_webhook_endpoint, if: :youtrack?

  def youtrack_base_url = settings&.dig("base_url")
  def youtrack_project_id = settings&.dig("youtrack_project_id")&.to_s
  def youtrack_token = credentials_data["permanent_token"]

  # WebhookEndpoint links back to its integration through `config.integration_id`
  # (JSONB), not a real FK column — see youtrack-integration-tech-design-v6.md §4/§9.3 —
  # so this can't be a normal `has_one`.
  def youtrack_webhook_endpoint
    WebhookEndpoint.where(provider: "youtrack").find_by("config->>'integration_id' = ?", id.to_s)
  end

  validates :name, presence: true
  validates :provider, presence: true
  validate :project_belongs_to_same_company, if: -> { project_id.present? }
  validate :azure_devops_connection_is_scoped, if: :azure_devops?

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

  # A GitHub PAT connection has no installation to match on, so the scope alone
  # identifies it: one PAT connection per project (or per company, for the
  # company-wide rows that predate project scoping). Reconnecting replaces the
  # token on that row rather than stacking a second connection to the same
  # account — a PAT expires and gets re-pasted often, and every re-paste would
  # otherwise leave the previous, dead connection behind for someone to clean up.
  def self.find_or_build_github_for_pat(company:, connected_by:, project:)
    scoped =
      if project
        company.integrations.where(project_id: project.id, provider: :github)
      else
        company.integrations.company_wide.where(provider: :github)
      end

    scoped.find(&:github_pat?) ||
      company.integrations.build(provider: :github, connected_by: connected_by, project: project)
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

  # ----- Azure DevOps accessors -----
  #
  # Identity lives in `settings` (non-secret, serialized to the browser) and the
  # authoritative copy lives on the installation. These readers prefer the
  # installation so a stale settings blob can never widen reach; `settings` is
  # the display cache and the only source in PAT mode.

  def azure_auth_mode
    settings&.dig("auth_mode").presence || (azure_devops_installation_id ? "service_principal" : "pat")
  end

  def azure_service_principal?
    azure_devops? && azure_auth_mode == "service_principal"
  end

  def azure_pat?
    azure_devops? && azure_auth_mode == "pat"
  end

  def azure_organization_slug
    azure_devops_installation&.organization_slug || settings&.dig("organization_slug")
  end

  # A connection reaches one or more Azure projects inside its organization.
  #
  # It used to reach exactly one, and `azure_project_id` was a scalar in
  # settings. Connections made before the change still carry that key, so it is
  # read as a one-element list rather than migrated: the scalar is the truth for
  # those rows and rewriting settings in a migration would touch every customer
  # connection to change nothing.
  def azure_project_ids
    stored = settings&.dig("azure_project_ids")
    return Array(stored).map(&:to_s) if stored.present?

    Array(settings&.dig("azure_project_id")).map(&:to_s)
  end

  # id => name, for display. Names are not authorization: everything that
  # decides access uses the ids.
  def azure_project_names
    stored = settings&.dig("azure_project_names")
    return stored.to_h { |k, v| [ k.to_s, v.to_s ] } if stored.is_a?(Hash) && stored.present?

    legacy_id = settings&.dig("azure_project_id")
    legacy_name = settings&.dig("azure_project_name")
    legacy_id.present? && legacy_name.present? ? { legacy_id.to_s => legacy_name.to_s } : {}
  end

  def azure_project_name(project_id = nil)
    return azure_project_names[project_id.to_s] if project_id.present?

    azure_project_names.values.first
  end

  # The gate every Azure call passes: a project this connection was actually
  # given. Knowing an id is not enough — the ids are visible to anyone who can
  # read the organization.
  def azure_project_selected?(project_id)
    project_id.present? && azure_project_ids.include?(project_id.to_s)
  end

  # The single project, where there is exactly one. Callers that can accept a
  # default use this; tools that act on a caller-named project must not.
  #
  # Deliberately nil when the connection covers several. Returning "the first"
  # would make an unqualified call act on whichever project sorted first, which
  # is the failure this whole change exists to prevent — better a loud refusal
  # naming the ambiguity.
  def azure_default_project_id
    ids = azure_project_ids
    ids.one? ? ids.first : nil
  end

  # Reads naturally where a connection has one project, and is the same value.
  alias azure_project_id azure_default_project_id

  def azure_personal_access_token
    credentials_data["personal_access_token"]
  end

  def azure_enabled_capabilities
    Array(settings&.dig("enabled_capabilities"))
  end

  def azure_capability_enabled?(capability)
    azure_enabled_capabilities.include?(capability.to_s)
  end

  # ----- GitHub accessors -----

  # How this connection authenticates: "app" (a GitHub App installation, the
  # production path) or "pat" (a user's personal access token, for a developer
  # trying Aixle where no App can be installed).
  #
  # Connections made before PAT mode existed carry no `auth_mode` key, and they
  # are all App installations — hence the default, which is what lets them keep
  # working with no migration.
  def github_auth_mode
    return nil unless github?

    settings&.dig("auth_mode").presence == "pat" ? "pat" : "app"
  end

  def github_app?
    github? && github_auth_mode == "app"
  end

  def github_pat?
    github? && github_auth_mode == "pat"
  end

  # GitHub account (org or user) the App is installed on — or, in PAT mode, the
  # user the token belongs to. Recorded at connect time by
  # Github::IntegrationService; blank on integrations connected before that, and
  # on installations that never verified.
  def github_account_login
    settings&.dig("account_login")
  end

  def github_personal_access_token
    credentials_data["personal_access_token"]
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

  # An Azure connection names exactly one Azure project, so it cannot be
  # company-wide: a company-wide row would hand every project in the company the
  # same selected Azure project and the same credentials. Service-principal mode
  # additionally requires the approved binding, and that binding must belong to
  # this company and still approve the selected project.
  def azure_devops_connection_is_scoped
    errors.add(:project, "is required for an Azure DevOps integration") if project_id.blank?

    installation = azure_devops_installation
    if azure_auth_mode == "service_principal"
      return errors.add(:azure_devops_installation, "is required in service-principal mode") if installation.nil?
      errors.add(:azure_devops_installation, "belongs to another company") if installation.company_id != company_id

      selected = azure_project_ids
      errors.add(:azure_project_ids, "must name at least one Azure project") if selected.empty?
      outside = selected.reject { |id| installation.approved_project?(id) }
      if outside.any?
        errors.add(:azure_project_ids, "are not in the installation's approved scope: #{outside.join(', ')}")
      end
    elsif installation.present?
      errors.add(:azure_devops_installation, "must be absent in PAT mode")
    end
  end

  def encryption_key_setting
    Settings.encryption.integrations_key
  end

  def destroy_youtrack_webhook_endpoint
    youtrack_webhook_endpoint&.destroy
  end
end
