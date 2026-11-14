# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §11, §15 task 12e. A machine records the
# address it registered from and the user who minted its registration token
# ("Add machine"); the token carries the user to the machine. Machines
# registered before this show neither: runner data has no compatibility to keep
# until the feature has users (§12.2).
class AddFirstSeenIpAndCreatorToRunnerMachines < ActiveRecord::Migration[8.1]
  def change
    add_column :runner_environments, :first_seen_ip, :string
    add_reference :runner_environments, :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :runner_credentials, :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
