# frozen_string_literal: true

FactoryBot.define do
  factory :task_asset do
    sequence(:name) { |n| "Asset #{n}" }
    board_task { nil }
    author { nil }
    author_type { :human }
  end
end
