# frozen_string_literal: true

# "How to talk to an authorization server." One row per (issuer, client_id).
# source: "static" = materialized from Oauth::Providers registry (Settings-backed);
# "dcr" = RFC 7591 dynamic client registration; "cimd" = RFC "Client ID Metadata
# Document" (client_id is our hosted metadata-doc URL — no registration needed).
class OauthClient < ApplicationRecord
  include Encryptable

  # Sources produced by MCP OAuth discovery (attacker-influenced endpoints — the
  # callback constrains signed client ids to these so a static client can't be
  # smuggled through the mcp: branch).
  DISCOVERED_SOURCES = %w[dcr cimd].freeze

  has_many :oauth_credentials, dependent: :destroy

  validates :issuer, :authorization_endpoint, :token_endpoint, :client_id, :source, presence: true
  validates :client_id, uniqueness: { scope: :issuer }

  # Encrypted client secret (nil for public/PKCE-only clients).
  def client_secret=(val)
    self.encrypted_client_secret = val.present? ? encryptor.encrypt_and_sign(val) : nil
  end

  def client_secret
    return nil if encrypted_client_secret.blank?

    encryptor.decrypt_and_verify(encrypted_client_secret)
  # AES-GCM (this app's cipher) raises InvalidMessage on wrong-key/tampered
  # ciphertext; InvalidSignature is the CBC/HMAC-era name. Rescue both so a
  # rotated or corrupt key decrypts to nil instead of crashing (mirrors
  # Integration#credentials_data).
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # True when the token endpoint needs client_secret (confidential client).
  def confidential?
    encrypted_client_secret.present?
  end

  private

  def encryption_key_setting
    Settings.encryption.oauth_key
  end
end
