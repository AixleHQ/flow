# frozen_string_literal: true

FactoryBot.define do
  factory :project_team do
    project { nil } # pass project: explicitly
    sequence(:name) { |n| "Team #{n}" }
    strategy { "priority" }
  end

  factory :project_team_member do
    project_team { nil } # pass project_team: and user: explicitly
    user { nil }
    sequence(:position)
  end
end
