# frozen_string_literal: true

FactoryBot.define do
  factory :board do
    sequence(:name) { |n| "Board #{n}" }
    project { nil }

    trait :with_preset do
      preset_origin { "dev_team" }
    end
  end
end
