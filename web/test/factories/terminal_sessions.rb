# frozen_string_literal: true

FactoryBot.define do
  factory :terminal_session do
    user { nil }     # Default: no user (requires explicit user:)
    project { nil }  # Default: no project
    session_type { "auth_setup" }
    agent_type { "claude_code" }
    state { "not_started" }
    temporal_workflow_id { nil }
    temporal_run_id { nil }
    container_id { nil }
    artifacts_path { nil }
    error_message { nil }
    metadata { {} }
    started_at { nil }
    finished_at { nil }
    collected_at { nil }

    # == Association Traits ==

    trait :with_user do
      association :user
    end

    trait :with_project do
      association :project
    end

    # Note: For most tests, pass user: explicitly:
    #   create(:terminal_session, user: user)

    # == Session Type Traits ==

    trait :auth_setup do
      session_type { "auth_setup" }
      project { nil }
    end

    trait :agent_session do
      session_type { "agent_session" }
    end

    # == State Traits ==

    trait :running do
      state { "running" }
      container_id { "container-#{SecureRandom.hex(8)}" }
      route_token { SecureRandom.hex(16) }
      started_at { Time.current }
    end

    trait :collected do
      state { "collected" }
      container_id { "container-#{SecureRandom.hex(8)}" }
      artifacts_path { "/tmp/artifacts/#{SecureRandom.hex(8)}.json" }
      started_at { 10.minutes.ago }
      finished_at { 5.minutes.ago }
      collected_at { Time.current }
    end

    trait :failed do
      state { "failed" }
      error_message { "Container failed to start" }
      started_at { 5.minutes.ago }
    end

    trait :cancelled do
      state { "cancelled" }
      started_at { 5.minutes.ago }
    end
  end
end
