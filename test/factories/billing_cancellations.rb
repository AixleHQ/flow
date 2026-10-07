# frozen_string_literal: true

FactoryBot.define do
  factory :billing_cancellation do
    company
    reason { "too_expensive" }
    cancels_at { 20.days.from_now }
  end
end
