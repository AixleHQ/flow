# frozen_string_literal: true

FactoryBot.define do
  factory :act_as_consent do
    user
    project
    company { project.company }
    provider { "github" }
    in_own_tasks { false }
    in_others_tasks { false }

    trait :own do
      in_own_tasks { true }
    end

    trait :others do
      in_others_tasks { true }
    end
  end
end
