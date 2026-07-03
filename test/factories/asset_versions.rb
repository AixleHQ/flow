# frozen_string_literal: true

FactoryBot.define do
  factory :asset_version do
    asset
    uploaded_by factory: %i[user]
    version { 1 }
    content_type { "text/markdown" }
    file_size { 1024 }
    source { :upload }

    trait :with_file do
      after(:build) do |version|
        version.file = AssetFileUploader.upload(StringIO.new("test file content"), :store)
      end
    end
  end
end
