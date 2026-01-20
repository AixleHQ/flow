class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      # Company can be null for super_admin users (platform-level admins)
      t.references :company, null: true, foreign_key: true
      t.citext :email, null: false
      t.string :name, null: false
      t.string :password_digest
      t.string :otp_secret
      t.string :status, null: false, default: "active"
      # Role within company: admin, collaborator
      # super_admin is a special platform-level role (company_id is null)
      t.string :role, null: false, default: "collaborator"

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :status
    add_index :users, :role
    add_index :users, [:company_id, :email], unique: true, where: "company_id IS NOT NULL"
  end
end
