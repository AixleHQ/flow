class CurrentUserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :role, :state, :created_at, :updated_at
end
