# frozen_string_literal: true

# A key Flow signs its OpenID Connect tokens with (docs/design/aws-oidc-integration.md §5.4).
# One set per instance, shared by every issuer: the issuer string, not the key, tells
# tenants apart. AwsOidc::SigningKeys owns the lifecycle; nothing else writes these rows.
class OidcSigningKey < ApplicationRecord
  include Encryptable

  encryption_key :integrations_key
  encrypted_column :encrypted_private_key

  STATES = %w[next current retired].freeze

  validates :kid, presence: true, uniqueness: true
  validates :state, inclusion: { in: STATES }
  validates :public_jwk, :encrypted_private_key, presence: true

  self.filter_attributes += [ :encrypted_private_key ]

  scope :in_state, ->(state) { where(state: state) }

  def private_key=(pem)
    self.encrypted_private_key = encrypt_secret(pem, column: "encrypted_private_key")
  end

  def private_key
    OpenSSL::PKey::RSA.new(decrypt_secret(encrypted_private_key, column: "encrypted_private_key"))
  end
end
