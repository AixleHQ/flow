# frozen_string_literal: true

FactoryBot.define do
  factory :tool_result do
    execution_id { ToolResult.generate_id }
    state { "processing" }
    association :tool, factory: [:tool, :internal], name: "test_tool", display_name: "Test Tool"

    trait :completed do
      state { "completed" }
      exit_code { 0 }
      duration_ms { 1500 }
    end

    trait :failed do
      state { "failed" }
      exit_code { 1 }
      error { "Exited with code 1" }
      duration_ms { 800 }
    end

    trait :expired do
      state { "expired" }
      exit_code { 0 }
      duration_ms { 500 }
    end
  end
end
