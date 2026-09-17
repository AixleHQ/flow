# frozen_string_literal: true

# A server-side login session (AD-6). Named AuthSession rather than Session
# because "session" already means an agent terminal session here.
#
# Its proofs APPEND: every successful authentication adds one, and a company is
# satisfied when the intersection of those proofs with its currently-enabled
# providers is non-empty.
class AuthSession < ApplicationRecord
  TOKEN_PREFIX = "as_"

  belongs_to :user

  has_many :proofs, class_name: "AuthSessionProof", dependent: :destroy

  validates :token_digest, presence: true, uniqueness: true

  scope :live, -> { where(revoked_at: nil) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_live_by_token(token)
    return nil if token.blank?

    live.find_by(token_digest: digest(token))
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    return if revoked?

    update!(revoked_at: Time.current)
  end

  # The provider ids this session has proved. Live rows only — a proof naming a
  # deleted provider is gone with it.
  def proved_provider_ids
    proofs.pluck(:identity_provider_id)
  end
end
