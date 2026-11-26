# frozen_string_literal: true

class AwsOidcRolePickerResource < ApplicationResource
  typelize :number
  attribute :id do |role|
    role.id
  end

  typelize :string
  attribute :name do |role|
    role.name
  end

  typelize :string
  attribute :role_arn do |role|
    role.role_arn
  end

  typelize :string
  attribute :account_id do |role|
    role.account_id
  end

  typelize :string
  attribute :region do |role|
    role.region
  end
end
