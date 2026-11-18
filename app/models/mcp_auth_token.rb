# frozen_string_literal: true

# An access or refresh token of an MCPAuthGrant. Only the digest is stored; the
# plaintext leaves the server once, in the token response.
#
# Refresh tokens rotate: using one marks it `rotated_at` and issues a new pair.
# Presenting it again shortly after is a client retrying a refresh whose
# response it lost, and gets a fresh pair; presenting it later means a copy is
# in someone else's hands, and the whole grant ends (OAuth 2.1 §4.3.1).
class MCPAuthToken < ApplicationRecord
  KINDS = %w[access refresh].freeze
  PREFIXES = { "access" => "aoat_", "refresh" => "aort_" }.freeze
  ACCESS_TTL = 1.hour
  REFRESH_TTL = 30.days
  REUSE_GRACE = 30.seconds

  belongs_to :grant, class_name: "MCPAuthGrant", inverse_of: :tokens

  validates :kind, inclusion: { in: KINDS }

  def self.access_token?(value) = value.to_s.start_with?(PREFIXES["access"])

  # Returns the plaintext.
  def self.issue!(grant, kind, now: Time.current)
    value = "#{PREFIXES.fetch(kind)}#{SecureRandom.urlsafe_base64(32)}"
    ttl = kind == "access" ? ACCESS_TTL : REFRESH_TTL
    create!(grant: grant, kind: kind, token_digest: MCPAuthGrant.digest(value), expires_at: now + ttl, created_at: now)
    value
  end

  def self.find_by_plaintext(value, kind:)
    return nil unless value.is_a?(String) && value.start_with?(PREFIXES.fetch(kind))

    find_by(kind: kind, token_digest: MCPAuthGrant.digest(value))
  end

  # The live grant an access token stands for, or nil: unknown, expired,
  # revoked, or its user can no longer sign in.
  def self.authenticate(value)
    token = find_by_plaintext(value, kind: "access")
    return nil if token.nil? || token.expires_at.past?

    grant = MCPAuthGrant.active.find_by(id: token.grant_id)
    grant if grant && User.authenticatable.exists?(id: grant.user_id)
  end

  def expired? = expires_at.past?

  # True for the one caller that rotated this token; false for a concurrent second.
  def rotate!(now = Time.current)
    self.class.where(id: id, rotated_at: nil).update_all(rotated_at: now) == 1
  end

  def within_reuse_grace?(now = Time.current) = rotated_at.present? && rotated_at > now - REUSE_GRACE
end
