# frozen_string_literal: true

class AddInvitationFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :invited_by, foreign_key: { to_table: :users }, null: true
    add_column :users, :invited_at, :datetime
  end
end
