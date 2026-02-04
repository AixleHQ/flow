# frozen_string_literal: true

FactoryBot.define do
  factory :project do
    name
    description
    state { :active }
    preferred_artifacts_language { "en" }
    company { nil }  # Default: no company (requires explicit company:)
    owner { nil }    # Default: no owner (requires explicit owner:)

    # == Association Traits ==

    trait :with_company do
      association :company
    end

    trait :with_owner do
      association :owner, factory: :user
    end

    # Note: For most tests, pass company: and owner: explicitly:
    #   create(:project, company: company, owner: user)

    # == State Traits ==

    trait :archived do
      state { :archived }
    end
  end
end
