# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.2, §6.2, §15 task 12c:
# runner_environments.last_heartbeat_at, the last time the platform heard from a
# `manual` machine (any authenticated request, Runners::Liveness.record!). Null
# for a machine that has not been heard since this column landed: it reads as
# offline until its next poll, at most 25 s.
class AddLastHeartbeatAtToRunnerEnvironments < ActiveRecord::Migration[8.1]
  def change
    add_column :runner_environments, :last_heartbeat_at, :datetime
  end
end
