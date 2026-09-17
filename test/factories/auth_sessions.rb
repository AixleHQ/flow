# frozen_string_literal: true

FactoryBot.define do
  factory :auth_session do
    user
    token_digest { AuthSession.digest(SecureRandom.hex(16)) }
    last_seen_at { Time.current }
  end
end
