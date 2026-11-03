# frozen_string_literal: true

FactoryBot.define do
  factory :legal_acceptance do
    user
    user_email { user&.email }
    document { LegalDocument::TERMS_OF_USE.key }
    version { LegalDocument::TERMS_OF_USE.version }
    accepted_at { Time.current }

    trait :terms_of_service do
      company
      company_name { company&.name }
      company_email_domain { company&.email_domain }
      document { LegalDocument::TERMS_OF_SERVICE.key }
      version { LegalDocument::TERMS_OF_SERVICE.version }
    end
  end
end
