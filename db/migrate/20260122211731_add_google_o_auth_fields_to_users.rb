class AddGoogleOAuthFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :google_token, :string
    add_column :users, :google_refresh_token, :string
    add_column :users, :avatar_url, :string

    add_index :users, [ :provider, :uid ], unique: true
  end
end
