class CreateUsageStatistics < ActiveRecord::Migration[8.0]
  def change
    create_table :usage_statistics do |t|
      t.references :terminal_session, null: false, foreign_key: true, index: { unique: true }
      t.bigint :tokens, null: false, default: 0
      t.bigint :cost_cents, null: false, default: 0

      t.timestamps
    end
  end
end
