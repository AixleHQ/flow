# frozen_string_literal: true

FactoryBot.define do
  factory :agent do
    sequence(:name) { |n| "agent_#{n}" }
    title { "Agent #{name&.titleize}" }
    persona { "You are a helpful assistant for #{name}." }
    communication_style { "Concise and friendly" }
    principles { "Be accurate. Be helpful." }
    icon { "robot" }
    source { :custom }
    # Agents are Project-scoped only.
    scope factory: %i[project standalone]

    trait :with_project_scope do
      scope factory: %i[project standalone]
    end
  end
end
