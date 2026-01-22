class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :slug, null: false
      t.string :state, null: false
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :projects, :state
    add_index :projects, [:company_id, :slug], unique: true
    add_index :projects, [:company_id, :name], unique: true
  end
end
