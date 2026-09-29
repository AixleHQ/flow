# frozen_string_literal: true

FactoryBot.define do
  factory :company_auth_policy do
    company
    identity_provider
    enabled { true }
  end
end
