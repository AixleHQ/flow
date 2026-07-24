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
      company
    end

    trait :with_owner do
      owner factory: %i[user]
    end

    # Self-consistent valid project: a company plus an owner who belongs to it.
    # Used as the default scope target for the project-scoped resource factories
    # (agents/skills/workflows/mcp_servers) so a bare create(:agent) is valid.
    trait :standalone do
      company
      owner { association(:user, company: company) }
    end

    # Note: For most tests, pass company: and owner: explicitly:
    #   create(:project, company: company, owner: user)

    # == State Traits ==

    trait :archived do
      state { :archived }
    end
  end
end
