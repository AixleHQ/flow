# frozen_string_literal: true

# One row per token an agent was handed on a user's behalf
# (docs/design/github-user-identity.md §3.2). It is the audit trail, and the
# source of the values a session's log redaction masks: served logs are redacted
# when they are read, long after the tool call, so the token itself is kept.
# Rows are immutable. The token is the scoped one, never the user's own.
class UserTokenIssuance < ApplicationRecord
  include Encryptable

  encryption_key :oauth_key
  encrypted_column :encrypted_token

  belongs_to :terminal_session
  belongs_to :company
  belongs_to :project
  belongs_to :acting_for_user, class_name: "User"
  belongs_to :session_user, class_name: "User", optional: true
  belongs_to :oauth_credential, optional: true

  validates :tool_name, :provider, :target_login, :encrypted_token, presence: true

  scope :for_session, ->(session) { where(terminal_session_id: session.id) }

  self.filter_attributes += [ :encrypted_token ]

  # Immutable once written, like EntityVersion: the audit trail and the log redaction both rely on it.
  # Deletions still happen through the database's foreign keys.
  def readonly?
    persisted? || super
  end

  def token=(value)
    self.encrypted_token = value.present? ? encrypt_secret(value, column: "encrypted_token") : nil
  end

  def token
    decrypt_secret(encrypted_token, column: "encrypted_token")
  end

  # Tokens of a session that can be read; one the keys cannot open was never
  # readable by anyone, so it has nothing to mask.
  def self.token_values_for(session)
    for_session(session).filter_map do |issuance|
      issuance.token.presence
    rescue Encryptable::DecryptionError
      nil
    end
  end
end
