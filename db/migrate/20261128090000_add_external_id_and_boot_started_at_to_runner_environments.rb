# frozen_string_literal: true

# The columns of an environment the platform creates itself
# (docs/design/agent-runtimes/runner-coder.md §6). Additive: nothing allocated
# exists yet, so there is nothing to backfill.
#
# - `external_id`: the name of the machine the integration gave the environment,
#   unique within its runner.
# - `boot_started_at`: set with the first `external_id`; the clock of
#   `runners.bootstrap_timeout`.
class AddExternalIdAndBootStartedAtToRunnerEnvironments < ActiveRecord::Migration[8.1]
  def change
    add_column :runner_environments, :external_id, :string
    add_column :runner_environments, :boot_started_at, :datetime
    add_index :runner_environments, %i[runner_id external_id], unique: true, where: "external_id IS NOT NULL",
                                                                name: "index_runner_environments_on_runner_id_and_external_id"
  end
end
