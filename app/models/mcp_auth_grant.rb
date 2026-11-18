# frozen_string_literal: true

# One consent a person gave an MCP client on the authorize screen: the client may
# call the personal MCP server as them. Born with an authorization code; live
# once that code has been exchanged; carries the access and refresh tokens from
# then on.
#
# The grant keeps the sign-in proofs of the browser session that consented
# (Tools::PersonalMCP::Credential), so connecting from an SSO session reaches the
# SSO company.
class MCPAuthGrant < ApplicationRecord
  CODE_PREFIX = "aoac_"
  CODE_TTL = 5.minutes
  CLIENT_KINDS = %w[cimd dcr].freeze

  belongs_to :user
  has_many :tokens, class_name: "MCPAuthToken", foreign_key: :grant_id, inverse_of: :grant, dependent: :delete_all

  validates :client_id, :client_name, :redirect_uri, presence: true
  validates :client_kind, inclusion: { in: CLIENT_KINDS }

  # Connected and not yet ended: the code was exchanged, nobody revoked it, and
  # the refresh token is still within its lifetime.
  scope :active, -> { where(revoked_at: nil).where.not(code_used_at: nil).where(expires_at: Time.current..) }

  def self.digest(value) = Digest::SHA256.hexdigest(value)

  # Returns [grant, code]. The code is returned once and only its digest is kept.
  def self.authorize!(user:, client:, redirect_uri:, code_challenge:, resource:, scope:, proof_provider_ids:)
    code = "#{CODE_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    grant = create!(user: user, client_id: client.client_id, client_kind: client.kind, client_name: client.label,
                    redirect_uri: redirect_uri, code_challenge: code_challenge, resource: resource, scope: scope,
                    proof_provider_ids: proof_provider_ids, code_digest: digest(code),
                    code_expires_at: CODE_TTL.from_now)
    [ grant, code ]
  end

  def self.revoke_all_for!(user)
    where(user: user, revoked_at: nil).update_all(revoked_at: Time.current)
  end

  def revoke!
    update_column(:revoked_at, Time.current) if revoked_at.nil?
  end

  def revoked? = revoked_at.present?

  # Single use, enforced in the database: two exchanges of one code race on this
  # update, and only one of them sees its row change.
  def consume_code!
    self.class.where(id: id, code_used_at: nil).update_all(code_used_at: Time.current, updated_at: Time.current) == 1
  end

  def code_expired? = code_expires_at.nil? || code_expires_at.past?

  USE_GRANULARITY = 5.minutes

  def note_use!(now = Time.current)
    return if last_used_at && last_used_at > now - USE_GRANULARITY

    update_columns(last_used_at: now)
  end
end
