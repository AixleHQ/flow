# frozen_string_literal: true

# Generic inbound webhook gateway configuration. One row per registered source
# (Slack, a custom app, etc.) addressed by a stable URL slug. Verification
# strategy + secret + mapping config are DATA, not bespoke controller code — so
# adding a source is a row, not a new controller/route/job triple.
class CreateWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.string :slug, null: false
      t.string :provider, null: false, default: "generic"
      t.string :verification_strategy, null: false, default: "none"
      t.text :encrypted_secret
      t.jsonb :config, null: false, default: {}
      t.boolean :enabled, null: false, default: true

      t.references :project, foreign_key: { on_delete: :cascade }
      t.references :company, foreign_key: { on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :webhook_endpoints, :slug, unique: true
  end
end
