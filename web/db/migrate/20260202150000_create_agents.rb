# frozen_string_literal: true

class CreateAgents < ActiveRecord::Migration[7.2]
  def change
    create_table :agents do |t|
      t.string :name, null: false           # unique identifier (lowercase_underscore): "analyst", "pm"
      t.string :title, null: false          # display title: "Business Analyst", "Product Manager"
      t.string :icon                        # emoji for UI: "📊", "📋"
      t.text :persona, null: false          # role + identity (who the agent is)
      t.text :communication_style           # how the agent communicates
      t.text :principles                    # operating principles
      t.string :source, null: false, default: "custom" # custom | bmad_import
      t.string :scope_type, null: false     # Company | Project
      t.bigint :scope_id, null: false
      t.timestamps
    end

    add_index :agents, %i[scope_type scope_id name], unique: true
    add_index :agents, %i[scope_type scope_id]
  end
end
