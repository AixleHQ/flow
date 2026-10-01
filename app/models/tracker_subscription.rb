# frozen_string_literal: true

# How one connection's tracker events reach Aixle (docs/design/task-tracker-integrations.md §4.2).
#
# The endpoint token routes a delivery to this row and authorizes nothing: it
# appears in the tracker's webhook settings. The secret is the credential — a
# shared header token or an HMAC key, depending on the provider — encrypted and
# checked by the provider.
class TrackerSubscription < ApplicationRecord
  include Encryptable
  extend Enumerize

  encryption_key :integrations_key
  encrypted_column :encrypted_secret

  # `app`: the provider's own app delivers (the GitHub App, Linear's OAuth app), so there is nothing to register.
  enumerize :strategy, in: %i[manual api app], predicates: true
  enumerize :status, in: %i[pending active failing expired disabled], default: :pending, predicates: true, scope: true

  belongs_to :integration
  has_many :tracker_deliveries, dependent: :delete_all

  before_validation :assign_endpoint_token, on: :create
  validates :endpoint_token, presence: true, uniqueness: true

  scope :live, -> { where(status: %w[pending active failing]) }
  scope :expiring, ->(within) { live.where(strategy: "api").where(expires_at: ..within.from_now) }

  def secret
    decrypt_secret(encrypted_secret, column: "encrypted_secret") if encrypted_secret.present?
  end

  def secret=(value)
    self.encrypted_secret = value.present? ? encrypt_secret(value.to_s, column: "encrypted_secret") : nil
  end

  def callback_url(base_url = nil)
    host = base_url.presence || "#{Settings.protocol || 'https'}://#{Settings.domain}"
    "#{host.chomp('/')}/webhooks/trackers/#{endpoint_token}"
  end

  private

  def assign_endpoint_token
    self.endpoint_token ||= SecureRandom.urlsafe_base64(24)
  end
end
