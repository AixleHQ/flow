# frozen_string_literal: true

class CreateYoutrackPairings < ActiveRecord::Migration[8.1]
  def change
    create_table :youtrack_pairings do |t|
      t.string :public_id, null: false
      t.string :secret_digest, null: false
      t.string :code, null: false
      t.string :origin, null: false
      t.string :status, null: false, default: "pending"
      t.string :instance_url, null: false
      t.references :company, foreign_key: { on_delete: :cascade }
      t.references :project, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :cascade }
      t.references :integration, foreign_key: { on_delete: :nullify }
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :youtrack_pairings, :public_id, unique: true
    add_index :youtrack_pairings, :code, unique: true, where: "status = 'pending'"
  end
end
