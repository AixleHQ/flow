# frozen_string_literal: true

FactoryBot.define do
  factory :asset_version do
    association :asset
    association :uploaded_by, factory: :user
    version { 1 }
    content_type { "text/markdown" }
    file_size { 1024 }
    provenance { { source: "upload" } }
  end
end
