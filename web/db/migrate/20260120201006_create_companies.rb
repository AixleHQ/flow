class CreateCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.jsonb :settings, null: false, default: {}
      t.string :state, null: false

      t.timestamps
    end

    add_index :companies, :name, unique: true
    add_index :companies, :slug, unique: true
    add_index :companies, :state
  end
end
