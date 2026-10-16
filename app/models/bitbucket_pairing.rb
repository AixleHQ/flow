# frozen_string_literal: true

# One Connect handshake between a Bitbucket workspace and Aixle
# (docs/design/bitbucket-integration.md §5.5).
#
# A workspace administrator starts it from the Aixle Flow page in Bitbucket;
# the link it produces carries the secret in its fragment, and a signed-in Aixle
# user confirms it once. Only the secret's digest is kept.
class BitbucketPairing < ApplicationRecord
  EXPIRY = 10.minutes
  ACCOUNT_ID = /\A[A-Za-z0-9:_-]{1,128}\z/

  belongs_to :bitbucket_installation

  validates :public_id, :secret_digest, :account_id, :workspace_uuid, :expires_at, presence: true
  validates :account_id, format: { with: ACCOUNT_ID }

  scope :live, -> { where(expires_at: Time.current..) }

  # The new pairing and its secret, which exists nowhere else afterwards.
  def self.start!(installation:, account_id:)
    where(expires_at: ...Time.current).delete_all
    secret = SecureRandom.urlsafe_base64(32)
    pairing = create!(bitbucket_installation: installation, public_id: SecureRandom.urlsafe_base64(12),
                      secret_digest: digest(secret), account_id: account_id, workspace_uuid: installation.workspace_uuid,
                      expires_at: EXPIRY.from_now)
    [ pairing, secret ]
  end

  def self.digest(secret) = Digest::SHA256.hexdigest(secret.to_s)

  # The live pairing this id and secret open, or nil — an unknown id, a wrong
  # secret, a spent or expired pairing all answer alike.
  def self.open(public_id, secret)
    pairing = live.find_by(public_id: public_id.to_s)
    pairing if pairing&.authentic?(secret)
  end

  def authentic?(secret)
    secret.present? && ActiveSupport::SecurityUtils.secure_compare(secret_digest, self.class.digest(secret))
  end
end
