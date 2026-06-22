# frozen_string_literal: true

# A registered inbound webhook source for the generic gateway. Addressed by a
# stable URL slug (POST /webhooks/in/:slug). Everything provider-specific —
# how to verify the signature and which secret to use — lives here as data.
class WebhookEndpoint < ApplicationRecord
  include Encryptable
  extend Enumerize

  belongs_to :project, optional: true
  belongs_to :company, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :received_webhooks, dependent: :destroy

  enumerize :provider, in: %i[slack github gitlab generic], default: :generic, predicates: true
  # No predicates here: the `none` value would define a clashing `none?` method.
  enumerize :verification_strategy, in: %i[slack_v0 hmac_sha256 shared_token none], default: :none

  validates :slug, presence: true, uniqueness: true
  validates :provider, presence: true
  validates :verification_strategy, presence: true

  scope :active, -> { where(enabled: true) }

  def secret=(value)
    self.encrypted_secret = value.present? ? encryptor.encrypt_and_sign(value.to_s) : nil
  end

  def secret
    return nil if encrypted_secret.blank?

    encryptor.decrypt_and_verify(encrypted_secret)
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  private

  def encryption_key_setting
    Settings.encryption.integrations_key
  end
end
