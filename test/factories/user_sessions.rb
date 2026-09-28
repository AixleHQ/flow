# frozen_string_literal: true

FactoryBot.define do
  factory :user_session do
    user
    last_seen_at { Time.current }
  end
end
