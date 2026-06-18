# frozen_string_literal: true

# Deleting a Project destroys its agents before its workflows/steps (association
# declaration order), and steps.agent_id -> agents was RESTRICT, raising
# ActiveRecord::InvalidForeignKey (Sentry PALAD-AI-RAILS-1V). Nullify instead:
# agents can be company-scoped/shared, so steps must not be destroyed with them.
class FixStepsAgentFkOnDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :steps, :agents
    add_foreign_key :steps, :agents, on_delete: :nullify
  end

  def down
    remove_foreign_key :steps, :agents
    add_foreign_key :steps, :agents
  end
end
