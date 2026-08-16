# frozen_string_literal: true

# Audit trail for `get_config_item`: one row per value handed to an agent.
#
# Attaching a config item is gated on project access alone — any member who can
# reach a project can attach any of its items and read the value through the
# session MCP. The project IS the trust boundary, which makes this table the
# only artifact that can answer "which session read STRIPE_KEY, and who was
# driving it". It therefore has to be written at fetch time; the rows cannot be
# reconstructed afterwards from anything else we keep.
#
# The value is never stored here, and `config_item_id` is deliberately NOT a
# foreign key with `on_delete: :cascade` — deleting a secret must not erase the
# record that it was read.
class CreateConfigItemAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :config_item_accesses do |t|
      t.bigint :config_item_id, null: false
      t.bigint :terminal_session_id, null: false
      t.bigint :user_id
      # Denormalized so an audit row still reads after the item is deleted or
      # renamed — the whole point of the row is to survive the item.
      t.string :config_item_name, null: false
      t.string :item_type, null: false
      t.datetime :created_at, null: false
    end

    add_index :config_item_accesses, :config_item_id
    add_index :config_item_accesses, :terminal_session_id
    add_index :config_item_accesses, :created_at
  end
end
