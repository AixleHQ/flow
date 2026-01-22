# frozen_string_literal: true

FactoryBot.define do
  factory :project do
    name
    description
    state { :active }
    preferred_artifacts_language { "en" }
    association :company
    association :owner, factory: :user

    trait :archived do
      state { :archived }
    end
  end
end
