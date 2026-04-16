# frozen_string_literal: true

class UserResource < ApplicationResource
  attributes :id, :email, :name, :role, :state, :position, :invited_at, :created_at, :updated_at

  attribute :invited_by do |user|
    next nil unless user.invited_by.present?

    { id: user.invited_by.id, name: user.invited_by.name }
  end
end
