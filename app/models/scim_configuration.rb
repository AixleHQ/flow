# frozen_string_literal: true

# A company's SCIM endpoint credential (CAP-6).
#
# The token is a password: stored as a digest, shown once at generation, never
# retrievable afterwards.
class ScimConfiguration < ApplicationRecord
  PREFIX = "ascim_"

  belongs_to :company
  belongs_to :identity_provider, optional: true

  validates :token_digest, presence: true, uniqueness: true

  scope :enabled, -> { where(enabled: true) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.authenticate(token)
    return nil if token.blank? || !token.to_s.start_with?(PREFIX)

    enabled.find_by(token_digest: digest(token))
  end

  # Returns the plaintext once. Regenerating invalidates whatever the customer's
  # directory was using, which is the point of a rotation.
  def regenerate_token!
    token = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    update!(token_digest: self.class.digest(token))
    token
  end

  def touch_seen!
    return if last_seen_at.present? && last_seen_at > 1.minute.ago

    update_column(:last_seen_at, Time.current)
  end
end
