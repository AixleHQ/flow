# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §2.7, §6.7, §12.2: the reconnect grace is a
# fixed 15 minutes, not a runner setting. The config schema refuses unknown keys,
# so a runner that kept `reconnect_grace` would fail validation on its next save.
# Runner data has no compatibility to keep until the feature has users (§12.2), so
# the key is stripped from every runner's `config` instead of being tolerated.
class StripReconnectGraceFromRunnerConfig < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE runners SET config = config - 'reconnect_grace' WHERE config ? 'reconnect_grace'"
  end

  def down
    # The key is not restored: the value was a setting that no longer exists.
  end
end
