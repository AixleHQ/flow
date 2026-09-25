# frozen_string_literal: true

# A registered inbound webhook source for the generic gateway. Addressed by a
# stable URL slug (POST /webhooks/in/:slug). Everything provider-specific —
# how to verify the signature and which secret to use — lives here as data.
class WebhookEndpoint < ApplicationRecord
  include Encryptable

  encryption_key :integrations_key
  encrypted_column :encrypted_secret
  extend Enumerize

  belongs_to :project, optional: true
  belongs_to :company, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :received_webhooks, dependent: :destroy

  enumerize :provider, in: %i[slack github gitlab generic], default: :generic, predicates: true
  # No predicates here: the `none` value would define a clashing `none?` method.
  enumerize :verification_strategy, in: %i[slack_v0 hmac_sha256 shared_token none], default: :shared_token

  validates :slug, presence: true, uniqueness: true
  validates :provider, presence: true
  validates :verification_strategy, presence: true

  scope :active, -> { where(enabled: true) }

  # A workflow's inbound webhook. Unless the caller explicitly chooses otherwise
  # it demands a shared token, generated here, so the URL alone never fires the
  # workflow; the 128-bit slug is an address, not the credential.
  def self.create_for_trigger!(project:, created_by:, verification_strategy: nil, secret: nil)
    token = SecureRandom.hex(16)
    strategy = verification_strategy.presence || "shared_token"
    create!(
      slug: "wh-#{token}", provider: :generic, verification_strategy: strategy,
      secret: secret.presence || (strategy.to_s == "none" ? nil : SecureRandom.hex(24)),
      config: { "event_type" => "webhook.#{token}" },
      project: project, company: project.company, created_by: created_by
    )
  end

  def secret=(value)
    self.encrypted_secret = value.present? ? encrypt_secret(value.to_s, column: "encrypted_secret") : nil
  end

  def secret
    decrypt_secret(encrypted_secret, column: "encrypted_secret")
  end
end
