# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §6.3, §12.2: there is no ephemeral
# registration, so `runner_environments.ephemeral` goes. Runner data has no
# compatibility to keep until the feature has users (§12.2).
class RemoveEphemeralFromRunnerEnvironments < ActiveRecord::Migration[8.1]
  def change
    remove_column :runner_environments, :ephemeral, :boolean, default: false, null: false
  end
end
