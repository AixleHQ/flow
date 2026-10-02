# frozen_string_literal: true

# What a trigger tells the place its run came from (docs/design/teams-integration.md
# §8.2). Expands notify_on_failure into a mode, so a status card can follow; the
# boolean stays in step until every reader has moved over, then goes.
class AddStatusReportingToTriggerBindings < ActiveRecord::Migration[8.1]
  def up
    add_column :trigger_bindings, :status_reporting, :string, default: "failures", null: false
    execute "UPDATE trigger_bindings SET status_reporting = 'none' WHERE notify_on_failure = false"
  end

  def down
    remove_column :trigger_bindings, :status_reporting
  end
end
