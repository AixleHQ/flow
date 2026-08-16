# frozen_string_literal: true

FactoryBot.define do
  factory :project_favorite do
    project { nil }  # Default: no project (requires explicit project:)
    user { nil }     # Default: no user (requires explicit user:)

    # Note: For most tests, pass both explicitly:
    #   create(:project_favorite, project: project, user: user)
  end
end
