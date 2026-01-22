class UserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :state, :created_at, :updated_at
end
