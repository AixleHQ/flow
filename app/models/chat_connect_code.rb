# frozen_string_literal: true

# A one-time code that connects the channel it is posted in to a company
# (docs/design/shared-chat-workspaces.md §6.5, §8). Only its digest is stored:
# the code itself is shown once, to the person who asked for it.
class ChatConnectCode < ApplicationRecord
  PREFIX = "aixle-"
  # Crockford's Base32: no I, L, O or U, so a code read aloud or retyped survives.
  ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  LENGTH = 8
  PATTERN = /#{PREFIX}([#{ALPHABET}]{#{LENGTH}})/i
  TTL = 10.minutes
  MAX_OPEN_PER_COMPANY = 10

  belongs_to :company
  belongs_to :project
  belongs_to :trigger_binding, optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :chat_channel_connection, optional: true

  validates :provider, inclusion: { in: Chat::PROVIDERS.keys }
  validates :code_digest, :expires_at, presence: true
  validate :open_codes_capped, on: :create

  scope :usable, -> { where(redeemed_at: nil).where("expires_at > ?", Time.current) }

  # [record, code]. The code is not recoverable from the record.
  def self.issue!(project:, provider:, user:, trigger_binding: nil)
    code = "#{PREFIX}#{Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join}"
    record = create!(company_id: project.company_id, project: project, provider: provider.to_s,
                     requested_by: user, trigger_binding: trigger_binding,
                     code_digest: digest(code), expires_at: TTL.from_now)
    [ record, code ]
  end

  # The code inside a message, normalized; nil when the message holds none.
  def self.extract(text)
    match = text.to_s.match(PATTERN)
    match && "#{PREFIX}#{match[1].upcase}"
  end

  def self.digest(code) = Digest::SHA256.hexdigest(code.to_s.strip.downcase)

  def state
    return "redeemed" if redeemed_at
    return "expired" if expires_at <= Time.current

    "pending"
  end

  private

  def open_codes_capped
    return unless company_id && ChatConnectCode.usable.where(company_id: company_id).count >= MAX_OPEN_PER_COMPANY

    errors.add(:base, "Too many unused codes — use one or wait #{TTL.inspect} for them to expire")
  end
end
