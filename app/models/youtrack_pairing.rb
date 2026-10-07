# frozen_string_literal: true

# One Connect handshake between Aixle and the Aixle Flow app on a YouTrack
# instance (docs/design/task-tracker-integrations.md §12, phase 5).
#
# Started in Aixle, a pairing is bound to a project and its user from the start
# and only waits for the app. Started in the app, it waits for a signed-in user
# to type its code into Aixle's connect page. The app holds the secret, which is
# kept here only as a digest, and completes the pairing once.
class YoutrackPairing < ApplicationRecord
  extend Enumerize

  EXPIRY = 15.minutes
  # No 0/O or 1/I: the code is read off one screen and typed into another.
  CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars.freeze

  enumerize :origin, in: %i[aixle youtrack], predicates: true
  enumerize :status, in: %i[pending approved completed], default: :pending, predicates: true

  belongs_to :company, optional: true
  belongs_to :project, optional: true
  belongs_to :user, optional: true
  belongs_to :integration, optional: true

  validates :public_id, :secret_digest, :code, :instance_url, :expires_at, presence: true

  scope :live, -> { where(expires_at: Time.current..) }

  # The new pairing and its secret, which exists nowhere else afterwards.
  def self.start!(instance_url:, project: nil, user: nil)
    secret = SecureRandom.urlsafe_base64(32)
    attempts = 0
    begin
      pairing = create!(
        public_id: SecureRandom.urlsafe_base64(12), secret_digest: digest(secret), code: new_code,
        origin: project ? :aixle : :youtrack, status: project ? :approved : :pending, instance_url: instance_url,
        company: project&.company, project: project, user: user, approved_at: (Time.current if project),
        expires_at: EXPIRY.from_now
      )
    rescue ActiveRecord::RecordNotUnique
      retry if (attempts += 1) < 3
      raise
    end
    [ pairing, secret ]
  end

  def self.digest(secret) = Digest::SHA256.hexdigest(secret.to_s)

  def self.new_code
    raw = Array.new(8) { CODE_ALPHABET.sample(random: SecureRandom) }.join
    "#{raw[0, 4]}-#{raw[4, 4]}"
  end

  # The live pairing started in YouTrack whose code someone typed, however they
  # spaced or cased it.
  def self.awaiting_code(code)
    raw = code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    return if raw.length != 8

    live.where(origin: "youtrack", status: "pending").find_by(code: "#{raw[0, 4]}-#{raw[4, 4]}")
  end

  def authentic?(secret)
    secret.present? && ActiveSupport::SecurityUtils.secure_compare(secret_digest, self.class.digest(secret))
  end

  def expired? = expires_at <= Time.current

  def state
    return "completed" if completed?

    expired? ? "expired" : status.to_s
  end

  def approve!(project:, user:)
    update!(status: :approved, project: project, company: project.company, user: user, approved_at: Time.current)
  end

  def complete!(integration)
    update!(status: :completed, integration: integration, completed_at: Time.current)
  end
end
