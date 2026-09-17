# frozen_string_literal: true

# What can authenticate someone (AD-4).
#
# A DEPLOYMENT-scoped provider is a singleton per kind and belongs to the
# installation: one password provider, one Google provider. A COMPANY-scoped
# provider is one customer's own connection (their OIDC issuer, their SAML
# metadata) and belongs to exactly that company.
#
# The split exists because password and Google are not per-company: forcing them
# into a per-company row would mean one identity per company for a user with one
# password, and would force company-first login.
class IdentityProvider < ApplicationRecord
  extend Enumerize
  include Encryptable

  DEPLOYMENT_KINDS = %i[password google microsoft passkey magic_link totp].freeze
  # Company-scoped kinds are the ones a customer can connect themselves. Entra
  # is deliberately NOT here: it runs through one deployment-wide OmniAuth
  # strategy, and a kind that nothing can create or start is unreachable code
  # dressed up as a feature.
  COMPANY_KINDS = %i[oidc saml].freeze

  enumerize :kind, in: (DEPLOYMENT_KINDS | COMPANY_KINDS), predicates: true, scope: true
  enumerize :scope, in: %i[deployment company], predicates: true, scope: true

  belongs_to :company, optional: true

  has_many :user_identities, dependent: :restrict_with_error
  has_many :company_auth_policies, dependent: :destroy
  has_many :auth_session_proofs, dependent: :destroy

  validates :kind, presence: true
  validates :scope, presence: true
  validate :company_matches_scope

  scope :deployment_scoped, -> { where(scope: "deployment") }
  scope :for_company, ->(company) { where(company: company) }

  # Deployment-scoped providers are installation infrastructure, not data a
  # human curates: they exist wherever the app runs. Idempotent provisioning
  # keeps every environment — production, a fresh test database loaded from
  # schema.rb, a self-hoster's first boot — identical without a seeding ritual.
  def self.deployment!(kind)
    find_or_create_by!(kind: kind.to_s, scope: "deployment") do |provider|
      provider.name = kind.to_s.humanize
    end
  rescue ActiveRecord::RecordNotUnique
    # Two web processes can reach a lazily-provisioned singleton at the same
    # moment; the partial unique index is what makes that safe, and the loser of
    # the race simply reads the row the winner wrote.
    find_by!(kind: kind.to_s, scope: "deployment")
  end

  def self.password
    deployment!("password")
  end

  def display_name
    name.presence || kind.to_s.humanize
  end

  # A customer's OIDC client secret. Same storage shape as OauthClient: encrypted
  # at rest under the oauth key, never a plaintext column.
  def client_secret=(value)
    self.encrypted_secret = value.present? ? encryptor.encrypt_and_sign(value) : nil
  end

  def client_secret
    return nil if encrypted_secret.blank?

    encryptor.decrypt_and_verify(encrypted_secret)
  end

  def issuer = config["issuer"]
  def client_id = config["client_id"]
  def tenant_id = config["tenant_id"]

  private

  def encryption_key_setting
    Settings.encryption.oauth_key
  end

  # Mirrors the database check constraint; the constraint is the enforcement,
  # this is the readable error.
  def company_matches_scope
    if scope == "deployment" && company_id.present?
      errors.add(:company, "must be blank for a deployment-scoped provider")
    elsif scope == "company" && company_id.blank?
      errors.add(:company, "is required for a company-scoped provider")
    end
  end
end
