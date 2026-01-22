# frozen_string_literal: true

FactoryBot.define do
  factory :project_collaborator do
    association :project
    association :user
  end
end
