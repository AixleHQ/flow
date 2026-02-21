# frozen_string_literal: true

class CreateTools < ActiveRecord::Migration[7.2]
  def change
    create_table :tools do |t|
      t.string :name, null: false           # unique identifier (lowercase_underscore)
      t.string :display_name, null: false   # human-readable name
      t.text :description
      t.string :kind, null: false, default: "custom"  # internal | custom
      t.string :scope_type                  # Company | Project (null for internal)
      t.bigint :scope_id                    # company_id/project_id (null for internal)
      t.string :docker_image                # Docker image for custom tools
      t.text :command                       # command template with {{param}} placeholders
      t.jsonb :required_config_items, default: []  # ["API_KEY", "DATABASE_URL"]
      t.jsonb :input_schema, default: {}    # JSON Schema for parameters
      t.boolean :enabled, default: true
      t.timestamps
    end

    add_index :tools, %i[scope_type scope_id name], unique: true
    add_index :tools, :kind
  end
end
