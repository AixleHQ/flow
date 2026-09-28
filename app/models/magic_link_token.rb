# frozen_string_literal: true

# A single-use, short-lived sign-in link (CAP-4).
#
# Deliberately not the invitation token shape: an invitation is 7-day and
# reusable until consumed, and a login link must be neither. Single use is a
# database fact here, enforced in the same transaction that signs the person in.
class MagicLinkToken < ApplicationRecord
  TTL = 15.minutes
  PREFIX = "aml_"

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :live, -> { where(consumed_at: nil).where(expires_at: Time.current..) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # Returns [record, plaintext_token]. The plaintext is never stored and is
  # returned exactly once, to be emailed.
  def self.issue!(user, requested_ip: nil)
    token = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    record = create!(
      user: user, token_digest: digest(token),
      expires_at: TTL.from_now, requested_ip: requested_ip
    )
    [ record, token ]
  end

  # Consumes the token and returns its user, or nil when the link is unknown,
  # expired, or already used. The row is locked and re-checked so two clicks in
  # two tabs cannot both succeed.
  def self.consume(token)
    record = live.find_by(token_digest: digest(token))
    return nil if record.nil?

    consumed = record.with_lock do
      next false if record.consumed_at.present?

      record.update!(consumed_at: Time.current)
      true
    end
    consumed ? record.user : nil
  end
end
