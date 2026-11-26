# frozen_string_literal: true

# One row per STS exchange made for a session (docs/design/aws-oidc-integration.md §7.3).
# It is the integration's activity log, and the source of the values the session's log
# redaction masks: collected logs are redacted when they are read, long after the
# exchange, so the secret halves of the credentials are kept, encrypted.
class AwsOidcCredentialIssuance < ApplicationRecord
  include Encryptable

  encryption_key :integrations_key
  encrypted_column :encrypted_secrets

  belongs_to :aws_oidc_role, optional: true
  belongs_to :project
  belongs_to :terminal_session, optional: true
  belongs_to :step_run, optional: true
  belongs_to :user, optional: true

  validates :role_name, :role_arn, :subject, :jti, :access_key_id, :encrypted_secrets, :expires_at, presence: true

  self.filter_attributes += [ :encrypted_secrets ]

  scope :for_session, ->(session) { where(terminal_session_id: session.id) }

  def readonly?
    persisted? || super
  end

  def self.secret_values_for(session)
    for_session(session).flat_map do |issuance|
      issuance.secrets.values_at("secret_access_key", "session_token")
    rescue Encryptable::DecryptionError
      []
    end.compact_blank
  end

  def secrets=(hash)
    self.encrypted_secrets = encrypt_secret(hash.to_json, column: "encrypted_secrets")
  end

  def secrets
    JSON.parse(decrypt_secret(encrypted_secrets, column: "encrypted_secrets"))
  end
end
