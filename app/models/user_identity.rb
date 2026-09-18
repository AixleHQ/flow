# frozen_string_literal: true

# One external (or local) identity belonging to a user (AD-3).
#
# Identity is (provider, subject) — never email. `subject` is the provider's
# immutable identifier: OIDC `sub`, Entra `oid`, or, for the local password
# provider, the user's own id. Writes go through Auth::IdentityResolver and
# nowhere else.
class UserIdentity < ApplicationRecord
  belongs_to :user
  belongs_to :identity_provider

  validates :subject, presence: true
  validates :subject, uniqueness: { scope: :identity_provider_id }

  delegate :kind, to: :identity_provider

  scope :for_kind, ->(kind) { joins(:identity_provider).where(identity_providers: { kind: kind }) }

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end
end
