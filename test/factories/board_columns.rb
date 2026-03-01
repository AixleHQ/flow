# frozen_string_literal: true

FactoryBot.define do
  factory :board_column do
    sequence(:name) { |n| "Column #{n}" }
    board { nil }
  end
end
