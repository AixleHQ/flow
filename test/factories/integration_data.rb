# frozen_string_literal: true

FactoryBot.define do
  factory :integration_data do
    integration
    sequence(:key) { |n| "key-#{n}" }
    value { {} }
    expires_at { nil }

    trait :expired do
      expires_at { 30.minutes.ago }
    end

    trait :future_expiry do
      expires_at { 30.minutes.from_now }
    end

    trait :workspace_lock do
      sequence(:key) { |n| "coder:workspace_lock:ws-#{n}" }
      value do
        {
          kind:                "workspace_lock",
          workspace_id:        SecureRandom.uuid,
          terminal_session_id: SecureRandom.hex(4),
          acquired_at:         Time.current.iso8601
        }
      end
    end
  end
end
