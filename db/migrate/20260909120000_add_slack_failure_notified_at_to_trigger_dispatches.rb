# frozen_string_literal: true

class AddSlackFailureNotifiedAtToTriggerDispatches < ActiveRecord::Migration[8.0]
  def change
    add_column :trigger_dispatches, :slack_failure_notified_at, :datetime
  end
end
