# frozen_string_literal: true

# One successful authentication inside a session (AD-6). Append-only: proving a
# second method never invalidates the first, which is what stops step-up
# ping-pong for a user who belongs to companies with disjoint policies.
class AuthSessionProof < ApplicationRecord
  belongs_to :auth_session
  belongs_to :identity_provider

  validates :proved_at, presence: true
  validates :identity_provider_id, uniqueness: { scope: :auth_session_id }
end
