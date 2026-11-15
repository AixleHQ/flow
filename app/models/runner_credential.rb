# frozen_string_literal: true

# A token the runner gateway accepts (docs/design/agent-runtimes/DESIGN.md
# §2.3, §9.2). Only the SHA-256 digest is stored: the token itself is returned
# once, by Runners::Credentials, and never kept.
#
# `registration` is a single-use `manual` registration token; once used it
# names the environment it created. `access` and `refresh` are an
# environment's pair, and every pair a refresh rotates into shares the first
# pair's `family_id` and names that refresh credential as `rotated_from`.
# `used_at` is when a registration or refresh token was spent, and when an
# access token was first accepted.
class RunnerCredential < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[registration access refresh], predicates: true

  belongs_to :runner
  belongs_to :company
  belongs_to :runner_environment, optional: true
  belongs_to :rotated_from, class_name: "RunnerCredential", optional: true
  # The user who minted a registration token; null for the rest, and once the user is deleted.
  belongs_to :created_by, class_name: "User", optional: true

  before_validation { self.company_id ||= runner&.company_id }

  validates :kind, presence: true
  validates :token_digest, presence: true
  validates :expires_at, presence: true
  validates :runner_environment, :family_id, presence: true, unless: :registration?

  scope :unrevoked, -> { where(revoked_at: nil) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_token(token, kind:)
    return nil if token.blank?

    find_by(token_digest: digest(token), kind: kind.to_s)
  end

  def expired?
    expires_at <= Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def used?
    used_at.present?
  end
end
