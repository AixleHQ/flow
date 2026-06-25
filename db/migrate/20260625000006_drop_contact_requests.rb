class DropContactRequests < ActiveRecord::Migration[8.0]
  def up
    drop_table :contact_requests
  end

  def down
    create_table :contact_requests, id: :uuid do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false

      t.timestamps
    end

    add_index :contact_requests, :email
    add_index :contact_requests, :created_at
  end
end
