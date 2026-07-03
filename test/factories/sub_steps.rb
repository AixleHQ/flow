# frozen_string_literal: true

FactoryBot.define do
  factory :sub_step do
    association :step
    sequence(:name) { |n| "SubStep #{n}" }
    sequence(:position) { |n| n }
    description { "A test sub-step" }
    required { true }
  end
end
