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
  # Credentials an operator registered by hand at the provider, for an authorization
  # server that refuses to let us register ourselves. Scoped to one MCP server: these
  # credentials belong to whoever pasted them, and another tenant's users must never
  # authorize into that OAuth app.
  SOURCE_MANUAL = "manual"
  # What the MCP callback branch will accept. Still excludes "static", which is the
  # point of the constraint.
  MCP_SOURCES = (DISCOVERED_SOURCES + [ SOURCE_MANUAL ]).freeze

  has_many :oauth_credentials, dependent: :destroy
  belongs_to :mcp_server, optional: true

  validates :client_id, :source, presence: true
  # A manual client is saved from a form, before any discovery has run, so it is the
  # one source that legitimately has no endpoints yet — MCP::OauthDiscoveryService
  # fills them in on the first connect. Every other source is born from discovery
  # and must arrive complete.
  validates :issuer, :authorization_endpoint, :token_endpoint, presence: true, unless: :manual?
  # Uniqueness follows the same split as the database indexes: shared clients are one
  # per (issuer, client_id), server-scoped ones are one per server.
  validates :client_id, uniqueness: { scope: :issuer }, unless: :manual?
  validates :mcp_server_id, presence: true, if: :manual?
  validates :mcp_server_id, absence: true, unless: :manual?

  def manual? = source == SOURCE_MANUAL

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
