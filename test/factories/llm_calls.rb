# frozen_string_literal: true

FactoryBot.define do
  factory :llm_call do
    terminal_session { association(:terminal_session, :agent_session, user: association(:user, :employee)) }
    sequence(:event_index)
    model            { "claude-sonnet-4-5" }
    provider         { "anthropic" }
    input_tokens     { 1000 }
    output_tokens    { 200 }
    cache_read_tokens  { 0 }
    cache_write_tokens { 0 }
    total_cents_precise { "0.01500000" }
    cost_basis       { "reported" }
    granularity      { "request" }
    source           { "otlp_log" }
    occurred_at      { 1.hour.ago }

    trait :with_workflow_run do
      workflow_run { association(:workflow_run) }
    end

    trait :with_step_run do
      step_run { association(:step_run) }
    end

    trait :unknown_cost do
      total_cents_precise { nil }
      cost_basis { "unknown" }
    end
  end
end
