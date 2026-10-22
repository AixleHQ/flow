# frozen_string_literal: true

# A one-time code that connects the channel it names to a company, once it is
# posted there (docs/design/shared-chat-workspaces.md §6.5, §8). Only its
# digest is stored: the code itself is shown once, to the person who asked for it.
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
  validates :code_digest, :expires_at, :channel_name, presence: true
  validate :open_codes_capped, on: :create

  scope :usable, -> { where(redeemed_at: nil).where("expires_at > ?", Time.current) }

  # [record, code]. The code is not recoverable from the record. `channel` is
  # the channel as people call it: "#deploys" or "deploys" in Slack; in Teams
  # "Team / Channel", or a group chat's name.
  def self.issue!(project:, provider:, user:, channel:, trigger_binding: nil)
    team, name = provider.to_s == Chat::TeamsProvider::KEY && channel.to_s.include?("/") ? channel.split("/", 2) : [ nil, channel ]
    code = "#{PREFIX}#{Array.new(LENGTH) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join}"
    record = create!(company_id: project.company_id, project: project, provider: provider.to_s,
                     requested_by: user, trigger_binding: trigger_binding,
                     channel_name: name.to_s.squish.delete_prefix("#").presence, team_name: team.to_s.squish.presence,
                     code_digest: digest(code), expires_at: TTL.from_now)
    [ record, code ]
  end

  # The code inside a message, normalized; nil when the message holds none.
  def self.extract(text)
    match = text.to_s.match(PATTERN)
    match && "#{PREFIX}#{match[1].upcase}"
  end

  # Keyed with a server secret: the code space is small enough that a plain
  # hash taken from a copy of the database would give the code back.
  def self.digest(code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("chat connect code", 32),
                            code.to_s.strip.downcase)
  end

  def self.comparable(name) = name.to_s.squish.delete_prefix("#").downcase

  # How people would write the channel this code is for.
  def channel_label
    return "##{channel_name}" if provider == Chat::SlackProvider::KEY

    team_name.present? ? "#{team_name} / #{channel_name}" : channel_name
  end

  # Why `conversation` is not the channel this code names, or nil when it is.
  # A Teams channel is named with its team: every team has a General.
  def channel_mismatch(conversation)
    if conversation.name.blank?
      return "#{Chat.provider(provider)&.label} did not say what this channel is called — reinstall the app so it " \
             "may read channel names"
    end
    if provider == Chat::TeamsProvider::KEY && conversation.channel? && team_name.blank?
      return "Name the team too for a Teams channel: Team / Channel"
    end

    matches = self.class.comparable(conversation.name) == self.class.comparable(channel_name) &&
              (team_name.blank? || self.class.comparable(conversation.team_name) == self.class.comparable(team_name))
    matches ? nil : "Posted in #{conversation.label}, but the code is for #{channel_label}"
  end

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
