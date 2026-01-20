class RemoveRoleAndOtpSecretFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_index :users, :role
    remove_column :users, :role, :string
    remove_column :users, :otp_secret, :string
  end
end
