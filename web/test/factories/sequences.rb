FactoryBot.define do
  sequence :name do |n|
    "Company #{n}"
  end

  sequence :company_name do |n|
    "Company #{n}"
  end

  sequence :email_domain do |n|
    domains = %w[com ai dev partners tech io co]
    "company-#{n}.#{domains.sample}"
  end

  sequence :password do |n|
    Faker::Internet.password(min_length: 8, max_length: 16, mix_case: true, special_characters: true)
  end

  sequence :email do |n|
    "user-#{n}@example.com"
  end

  sequence :text, aliases: [ :notes, :gherkin_syntax, :data, :ai_engine_content ] do |n|
    "Text content #{n}"
  end

  sequence :position, aliases: [ :id, :order ] do |n|
    n
  end

  sequence :ai_engine_timestamp do
    Time.current.iso8601(6) + "+00:00"
  end

  sequence :access_key do |n|
    "access_key_#{n}"
  end

  sequence :invitation_token do |n|
    SecureRandom.hex(16)
  end

  sequence :score do
    rand(1..10)
  end

  sequence :role do |n|
    Question.roles[n % Question.roles.size]
  end

  sequence :size do
    rand(1..1000)
  end

  sequence :format do
    %w[png jpg jpeg gif].sample
  end

  sequence :type do
    %w[image code document].sample
  end

  sequence :image_file_cache_data do
    image_file_cache_data
  end

  sequence :project_file_cache_data do
    project_file_cache_data
  end

  sequence :project_tar_file_cache_data do
    project_tar_file_cache_data
  end

  sequence :image_collection_file_cache_data do
    image_collection_file_cache_data
  end

  sequence :external_spec_file_cache_data do
    external_spec_file_cache_data
  end

  sequence :external_spec_file_store_data do
    external_spec_file_store_data
  end

  sequence :ai_engine_asset_type do
    AiEngineService::AI_ENGINE_ASSET_TYPES.values.sample
  end

  sequence :image_file_store_data do
    image_file_store_data
  end

  sequence :project_file_store_data do
    project_file_store_data
  end

  sequence :project_tar_file_store_data do
    project_tar_file_store_data
  end

  sequence :image_collection_file_store_data do
    image_collection_file_store_data
  end

  sequence :document_file_store_data do
    document_file_store_data
  end

  sequence :document_file_cache_data do
    document_file_cache_data
  end

  sequence :importance_level do
    rand(0..100)
  end

  sequence :prompt, aliases: [ :description, :justification ] do
    Faker::Lorem.paragraph
  end

  sequence :otp_secret do
    ROTP::Base32.random
  end

  sequence :mermaid_content do
    Faker::Lorem.paragraph
  end
end
