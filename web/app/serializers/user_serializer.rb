class UserSerializer < ApplicationSerializer
  attributes :id, :email, :name, :role, :state, :position, :invited_at, :created_at, :updated_at, :invited_by

  def invited_by
    return nil unless object.invited_by.present?

    {
      id: object.invited_by.id,
      name: object.invited_by.name
    }
  end
end
