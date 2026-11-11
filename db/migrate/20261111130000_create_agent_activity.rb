# frozen_string_literal: true

# What an agent was asked and which tools it used, for projects that share prompts with
# Aixle Insights (docs/design/insights-usage-export.md §3a).
class CreateAgentActivity < ActiveRecord::Migration[8.1]
  def change
    # The runtime's prompt id on a call, which joins it to the prompt that led to it.
    add_column :llm_calls, :prompt_ref, :string

    create_table :agent_prompts do |t|
      t.uuid :uid, null: false, default: -> { "gen_random_uuid()" }
      t.references :terminal_session, null: false, foreign_key: true, index: false
      t.references :workflow_run, foreign_key: true, index: false
      t.references :step_run, foreign_key: true, index: false
      t.string :source_key, null: false
      t.string :source, null: false
      t.datetime :occurred_at, null: false
      t.text :text, null: false
      t.integer :text_length, null: false
      t.boolean :truncated, null: false, default: false
      t.string :prompt_ref
      t.timestamps

      t.index :uid, unique: true
      t.index %i[terminal_session_id source_key], unique: true
      t.index %i[workflow_run_id occurred_at]
    end

    create_table :agent_tool_calls do |t|
      t.uuid :uid, null: false, default: -> { "gen_random_uuid()" }
      t.references :terminal_session, null: false, foreign_key: true, index: false
      t.references :workflow_run, foreign_key: true, index: false
      t.references :step_run, foreign_key: true, index: false
      t.string :source_key, null: false
      t.string :source, null: false
      t.datetime :occurred_at, null: false
      t.string :tool_name, null: false
      t.string :mcp_server
      t.jsonb :arguments
      t.boolean :success
      t.string :error
      t.integer :duration_ms
      t.string :prompt_ref
      t.timestamps

      t.index :uid, unique: true
      t.index %i[terminal_session_id source_key], unique: true
      t.index %i[workflow_run_id occurred_at]
    end
  end
end
