# frozen_string_literal: true

# One installation of the Aixle Flow Forge app on a Bitbucket workspace
# (docs/design/bitbucket-integration.md §5, §6.1).
#
# An installation proves only that THE APP can reach a workspace, never which
# Aixle company should own that reach: `company_id` stays null until a pairing
# started by a workspace admin is confirmed in Aixle (§5.5).
#
# It also holds the app token. Forge pushes a token with every invocation and
# offers no way to ask for one, so this cache is written by deliveries only and
# keeps whichever token lives longer.
class BitbucketInstallation < ApplicationRecord
  include Encryptable

  encryption_key :integrations_key
  encrypted_column :encrypted_access_token
  extend Enumerize

  enumerize :status, in: %i[active error uninstalled], default: :active, predicates: true, scope: true

  belongs_to :company, optional: true
  belongs_to :bound_by, class_name: "User", optional: true
  has_many :integrations, dependent: :restrict_with_error

  validates :forge_installation_id, :forge_environment_id, :workspace_uuid, presence: true
  validate :identity_is_immutable, on: :update

  scope :live, -> { where.not(status: "uninstalled") }
  scope :bound_to, ->(company) { where(company: company) }

  def bound? = company_id.present?

  # Stores `token` unless the one already held expires later. A token delivered
  # with a UI call can be older than one a scheduled tick just brought, and
  # storing it blindly turned live sessions' credentials into 401s (FRGE-2092).
  # The comparison is in the UPDATE so two deliveries racing cannot both win.
  def store_token!(token, expires_at:)
    now = Time.current
    self.class.where(id: id).update_all(last_invocation_at: now)
    return false if token.blank? || expires_at.blank? || expires_at <= now

    stored = self.class.where(id: id)
                       .where("token_expires_at IS NULL OR token_expires_at < ?", expires_at)
                       .update_all(encrypted_access_token: encrypt_secret(token.to_s, column: "encrypted_access_token"),
                                   token_expires_at: expires_at, updated_at: now)
    reload
    stored.positive?
  end

  # The token, while it has at least `min_remaining` seconds left; nil otherwise.
  # A cache, so an entry no key can read is a miss rather than an error.
  def usable_token(min_remaining:)
    return if encrypted_access_token.blank? || token_expires_at.blank?
    return if token_expires_at <= Time.current + min_remaining

    decrypt_secret(encrypted_access_token, column: "encrypted_access_token")
  rescue Encryptable::DecryptionError => e
    Rails.logger.warn("[BitbucketInstallation] #{e.message}; treating the cached token as absent")
    nil
  end

  def clear_token!
    update_columns(encrypted_access_token: nil, token_expires_at: nil, updated_at: Time.current)
  end

  def silent_since = last_invocation_at

  def self.ransackable_attributes(_auth_object = nil)
    %w[workspace_slug workspace_name status created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[company]
  end

  private

  # A binding that could move to another workspace would quietly hand one
  # workspace's approval to another.
  def identity_is_immutable
    %w[forge_installation_id forge_environment_id workspace_uuid].each do |attr|
      errors.add(attr, "cannot change on an existing installation") if public_send(:"#{attr}_changed?")
    end
  end
end
