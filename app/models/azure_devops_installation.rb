# frozen_string_literal: true

# The approved binding between one Aixle company and one Azure DevOps
# organization, for service-principal mode.
#
# Why this is not an Integration: a successful app-only API call proves that
# THE APPLICATION can reach an organization, never that the requesting company
# owns that access. Knowing a tenant ID, an organization slug or the shared
# client ID is not authority. This row is the record of an operator having
# verified that authority out of band; every discovery, attachment, tool call
# and Git credential issuance checks it.
#
# It also holds the app-only access token cache. There is no refresh token in
# the client-credentials flow, so "renew" means "acquire again with the app
# credential" — see AzureDevops::AppTokenService, which owns every write to the
# token columns.
class AzureDevopsInstallation < ApplicationRecord
  include Encryptable
  extend Enumerize

  enumerize :status, in: %i[inactive active error], default: :inactive, predicates: true, scope: true

  belongs_to :company
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :integrations, dependent: :restrict_with_error

  validates :tenant_id, presence: true
  validates :client_id, presence: true
  validates :organization_slug, presence: true
  validates :app_config_key, presence: true
  validate :azure_identity_is_immutable, on: :update
  validate :allowed_project_ids_are_guids

  scope :for_company, ->(company) { where(company: company) }
  scope :active, -> { where(status: "active") }

  # Azure organization slugs are `[A-Za-z0-9][A-Za-z0-9-]*` — the value goes
  # into a URL path we build, so it is validated rather than escaped away.
  ORGANIZATION_SLUG = /\A[A-Za-z0-9][A-Za-z0-9-]{0,62}\z/
  GUID = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  validates :organization_slug, format: { with: ORGANIZATION_SLUG, message: "is not a valid Azure organization name" }
  validates :tenant_id, format: { with: GUID, message: "must be a tenant GUID" }

  def organization_url
    "#{AzureDevops::AppConfig.api_host}/#{organization_slug}"
  end

  # Approved scope is an allowlist with no "unrestricted" state: an empty list
  # means no projects are reachable, which is why discovery intersects it with
  # what Azure returns rather than falling back to everything Azure allows.
  def approved_project?(project_id)
    project_id.present? && allowed_project_ids.include?(project_id.to_s)
  end

  def approve!(user:, project_ids:)
    update!(
      approved_by: user,
      approved_at: Time.current,
      allowed_project_ids: Array(project_ids).map(&:to_s).uniq
    )
  end

  # ----- Token cache (written only by AzureDevops::AppTokenService) -----

  def cached_access_token
    return nil if encrypted_access_token.blank?

    encryptor.decrypt_and_verify(encrypted_access_token)
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def cached_access_token=(value)
    self.encrypted_access_token = value.present? ? encryptor.encrypt_and_sign(value.to_s) : nil
  end

  # A cache entry is only usable for the exact credential generation and
  # resource it was minted under. Rotating the app certificate or changing the
  # Azure resource invalidates every entry without a sweep.
  def token_usable?(generation:, resource:, skew: 0)
    return false if encrypted_access_token.blank? || token_expires_at.blank?
    return false if token_credential_generation.to_s != generation.to_s
    return false if token_resource.to_s != resource.to_s

    token_expires_at > Time.current + skew
  end

  def clear_token_cache!
    update_columns(
      encrypted_access_token: nil,
      token_expires_at: nil,
      token_credential_generation: nil,
      token_resource: nil,
      updated_at: Time.current
    )
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[organization_slug tenant_id status created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[company approved_by]
  end

  private

  def encryption_key_setting
    Settings.encryption.integrations_key
  end

  # Ownership and Azure identity are what the authorization check reads. If they
  # could move while project integrations point here, an approved binding to one
  # organization would quietly become a binding to another.
  def azure_identity_is_immutable
    %w[company_id tenant_id client_id organization_slug].each do |attr|
      errors.add(attr, "cannot change on an existing installation") if public_send(:"#{attr}_changed?")
    end

    # These two start null and are filled in by verification; they may be SET
    # once, never rewritten.
    %w[organization_id service_principal_object_id].each do |attr|
      was = public_send(:"#{attr}_was")
      errors.add(attr, "is verified and cannot change") if public_send(:"#{attr}_changed?") && was.present?
    end
  end

  def allowed_project_ids_are_guids
    bad = Array(allowed_project_ids).reject { |id| id.to_s.match?(GUID) }
    return if bad.empty?

    errors.add(:allowed_project_ids, "must be Azure project GUIDs")
  end
end
