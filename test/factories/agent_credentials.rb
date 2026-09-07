# frozen_string_literal: true

FactoryBot.define do
  factory :agent_credential do
    user { nil }
    agent_type { "claude_code" }
    config_data do
      { "api_key" => "test-token-#{SecureRandom.hex(8)}", "theme" => "dark" }
    end
    metadata { { collected_at: Time.current } }
    last_used_at { nil }
    expires_at { nil }

    # == Association Traits ==

    trait :with_user do
      user
    end

    # Note: For most tests, pass user: explicitly:
    #   create(:agent_credential, user: user)

    # A credential belongs to a (user, company) pair — billing is per company —
    # and AgentCredential validates that the owner is a member of it. Callers
    # overwhelmingly pass only `user:`, so derive the company from that user's
    # membership, creating one when the user has none rather than inventing an
    # unrelated company the validation would (correctly) reject.
    before(:create) do |credential|
      next if credential.company_id.present?

      membership = if credential.user
        credential.user.company_memberships.first ||
          FactoryBot.create(:company_membership, user: credential.user)
      else
        # No user given either: build a coherent trio, since the credential
        # validates that its owner is a member of its company.
        FactoryBot.create(:company_membership).tap { |m| credential.user = m.user }
      end
      credential.company = membership.company
    end

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

    trait :grok do
      agent_type { "grok" }
    end

    # == State Traits ==

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :errored do
      status { "error" }
      refresh_error { "invalid_grant — reconnection required" }
      refresh_failure_count { 1 }
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
    end
  end
end
