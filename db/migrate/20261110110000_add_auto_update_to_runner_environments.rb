# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.2, §14.4, task 10:
# runner_environments.auto_update, false for a `manual` machine configured with
# `aixle-runner configure --no-auto-update`. Such a machine is never offered an
# update (Runners::Release.update_for). Every machine registered so far updates
# itself, as the default says.
class AddAutoUpdateToRunnerEnvironments < ActiveRecord::Migration[8.1]
  def change
    add_column :runner_environments, :auto_update, :boolean, null: false, default: true
  end
end
