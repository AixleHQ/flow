# frozen_string_literal: true

FactoryBot.define do
  factory :aws_oidc_role do
    integration factory: %i[integration aws_oidc]
    sequence(:name) { |n| "role-#{n}" }
    role_arn { "arn:aws:iam::123456789012:role/flow-diagnostics" }
    region { "eu-west-1" }
    session_duration_seconds { 3600 }
  end
end
