# frozen_string_literal: true

FactoryBot.define do
  factory :project_collaborator do
    project { nil }  # Default: no project (requires explicit project:)
    user { nil }     # Default: no user (requires explicit user:)

    # == Association Traits ==

    trait :with_project do
      project
    end

    trait :with_user do
      user
    end

    # Note: For most tests, pass both explicitly:
    #   create(:project_collaborator, project: project, user: user)
  end
end
