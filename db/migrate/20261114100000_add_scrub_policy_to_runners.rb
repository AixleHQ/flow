# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §7.1, §7.2 (task 11a). A `manual` runner's
# `fresh` meant a reset after every session, which is now `reset`; `fresh` is a
# new machine or workspace per session and is not offered on `manual`. A machine
# counts the failed sessions in a row on it (`runners.max_consecutive_failures`
# of them take it out of rotation). Runner data has no compatibility to keep
# until the feature has users (§12.2).
class AddScrubPolicyToRunners < ActiveRecord::Migration[8.1]
  def up
    add_column :runner_environments, :consecutive_failures, :integer, default: 0, null: false
    execute "UPDATE runners SET reuse_policy = 'reset' WHERE runner_type = 'manual' AND reuse_policy = 'fresh'"
  end

  def down
    execute "UPDATE runners SET reuse_policy = 'fresh' WHERE runner_type = 'manual' AND reuse_policy = 'reset'"
    remove_column :runner_environments, :consecutive_failures
  end
end
