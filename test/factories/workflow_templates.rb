# frozen_string_literal: true

FactoryBot.define do
  factory :workflow_template do
    company
    owner { association :user, company: company }
    sequence(:name) { |n| "template-#{n}" }
    description { "A reusable workflow template" }
    use_case { "Feature development" }
    visibility { "company" }

    trait :private do
      visibility { "private" }
    end
  end

  factory :workflow_template_version do
    workflow_template
    workflow { association :workflow, scope: workflow_template.company, kind: "template_snapshot" }
    published_by { workflow_template.owner }
    sequence(:version_number) { |n| n }
    published_at { Time.current }
  end
end
