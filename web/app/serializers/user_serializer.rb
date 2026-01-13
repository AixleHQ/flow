class UserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :status, :created_at, :updated_at
end
