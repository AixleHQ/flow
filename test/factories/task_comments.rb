# frozen_string_literal: true

FactoryBot.define do
  factory :task_comment do
    sequence(:body) { |n| "Comment #{n}" }
    board_task { nil }
    author { nil }
    author_type { :human }
  end
end
