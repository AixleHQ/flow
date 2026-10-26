# frozen_string_literal: true

# Runtime values of the flags declared in config/feature_flags.yml
# (docs/architecture/feature-flags.md).
# Rows are created the first time an admin sets a value, so a fresh install has none.
class CreateFeatureFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_flags do |t|
      t.string :key, null: false, index: { unique: true }
      # NULL is "use the declared default".
      t.boolean :enabled
      # Reserved for percentage rollout: no UI, never evaluated.
      t.integer :rollout_percent
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    create_table :feature_flag_overrides do |t|
      t.references :feature_flag, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, null: false
      t.text :reason, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index %i[feature_flag_id company_id], unique: true
    end
  end
end
