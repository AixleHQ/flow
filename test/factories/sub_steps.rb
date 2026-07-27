# frozen_string_literal: true

FactoryBot.define do
  factory :sub_step do
    step
    sequence(:name) { |n| "SubStep #{n}" }
    sequence(:position) { |n| n }
    instructions { "Do the test sub-step work" }
    required { true }
  end
end
