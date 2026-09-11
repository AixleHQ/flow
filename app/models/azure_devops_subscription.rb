# frozen_string_literal: true

# One Azure DevOps Service Hook subscription belonging to one project
# connection.
#
# The endpoint id and the password are deliberately different things. The id is
# in the URL Azure posts to, so it appears in Azure's subscription UI, its
# delivery history and its failure notifications — it routes a delivery to a
# connection and authorizes nothing. The password is the credential, stored
# encrypted and compared in constant time, because Azure webhooks authenticate
# with HTTP basic auth and send no signature of any kind. Copying GitHub's HMAC
# verification here would accept every unsigned request.
class AzureDevopsSubscription < ApplicationRecord
  include Encryptable
  extend Enumerize

  # `probation` is Azure's own state for a subscription that has failed often
  # enough to be throttled: it still exists, and new events are not delivered
  # while it lasts. Recorded rather than hidden, because "no events arriving" and
  # "nothing happened" look identical from here.
  enumerize :status, in: %i[pending active probation disabled error],
                     default: :pending, predicates: true, scope: true

  # The events the extension subscribes to. Each one is a notification to go and
  # re-read authoritative state — `git.pullrequest.merged` in particular reports
  # a merge ATTEMPT, and treating it as a completed pull request is how a gate
  # resolves on a merge that actually failed.
  EVENT_TYPES = %w[
    build.complete
    git.pullrequest.merged
    git.pullrequest.updated
  ].freeze

  belongs_to :integration
  has_many :azure_devops_deliveries, dependent: :delete_all

  validates :endpoint_id, presence: true, uniqueness: true
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validate :integration_is_azure

  scope :live, -> { where(status: %w[pending active probation]) }

  before_validation :assign_endpoint_id, on: :create

  def password
    return nil if encrypted_password.blank?

    encryptor.decrypt_and_verify(encrypted_password)
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def password=(value)
    self.encrypted_password = encryptor.encrypt_and_sign(value.to_s)
  end

  # Constant-time, and false for a blank candidate rather than "no password
  # configured means anything matches".
  def authenticate(candidate)
    stored = password
    return false if stored.blank? || candidate.blank?

    ActiveSupport::SecurityUtils.secure_compare(stored, candidate.to_s)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[endpoint_id event_type status created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[integration]
  end

  private

  def assign_endpoint_id
    self.endpoint_id ||= SecureRandom.urlsafe_base64(18)
    self.password = SecureRandom.urlsafe_base64(32) if encrypted_password.blank?
  end

  def integration_is_azure
    return if integration.blank? || integration.azure_devops?

    errors.add(:integration, "must be an Azure DevOps connection")
  end

  def encryption_key_setting
    Settings.encryption.integrations_key
  end
end
