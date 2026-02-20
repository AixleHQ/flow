# frozen_string_literal: true

FactoryBot.define do
  factory :agent_credential do
    user { nil }  # Default: no user (requires explicit user:)
    agent_type { "claude_code" }
    encrypted_config_data do
      {
        "~/.#{agent_type.split('_').first}/config" => "api_key: test-token-#{SecureRandom.hex(8)}\ntheme: dark"
      }.to_json
    end
    metadata { { collected_at: Time.current } }
    last_used_at { nil }
    expires_at { nil }

    # == Association Traits ==

    trait :with_user do
      association :user
    end

    # Note: For most tests, pass user: explicitly:
    #   create(:agent_credential, user: user)

    # == Agent Type Traits ==

    trait :claude_code do
      agent_type { "claude_code" }
    end

    trait :cursor_cli do
      agent_type { "cursor_cli" }
    end

    trait :codex do
      agent_type { "codex" }
    end

    trait :gemini_cli do
      agent_type { "gemini_cli" }
    end

    # == State Traits ==

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
    end
  end
end
