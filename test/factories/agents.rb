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
    scope { nil }

    trait :with_company_scope do
      association :scope, factory: :company
    end

    trait :with_project_scope do
      association :scope, factory: :project
    end

    trait :system do
      scope_type { "System" }
      scope_id { 0 }
      scope { nil }
    end
  end
end
