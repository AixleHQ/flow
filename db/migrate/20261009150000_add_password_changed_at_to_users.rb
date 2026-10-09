# frozen_string_literal: true

class AddPasswordChangedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_changed_at, :datetime
  end
end
