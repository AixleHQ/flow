# frozen_string_literal: true

FactoryBot.define do
  factory :board_task do
    sequence(:title) { |n| "Task #{n}" }
    board { nil }
    board_column { nil }
    task_type { :not_specified }
  end
end
