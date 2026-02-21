# frozen_string_literal: true

FactoryBot.define do
  factory :session_log do
    association :terminal_session
    name { "session.log" }
    file_size { 2048 }
    content_type { "text/plain" }

    trait :with_file do
      after(:build) do |log|
        log.file = SessionLogUploader.upload(StringIO.new("sample log content"), :store)
      end
    end
  end
end
