# frozen_string_literal: true

# Slack triggers that report failures now follow their runs with a status card
# instead (docs/design/teams-integration.md §15, phase 1); silenced ones stay silent.
# A `chat.message` trigger now names its messenger; until Teams, every one was Slack's.
class SwitchSlackTriggersToStatusCards < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE trigger_bindings SET filter_predicate = filter_predicate || '{"provider": "slack"}'::jsonb, updated_at = NOW()
      WHERE event_type = 'chat.message' AND NOT (filter_predicate ? 'provider')
    SQL
    execute <<~SQL.squish
      UPDATE trigger_bindings SET status_reporting = 'lifecycle', updated_at = NOW()
      WHERE status_reporting = 'failures'
        AND (event_type = 'slack.message' OR (event_type = 'chat.message' AND filter_predicate ->> 'provider' = 'slack'))
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE trigger_bindings SET status_reporting = 'failures', updated_at = NOW()
      WHERE status_reporting = 'lifecycle'
        AND (event_type = 'slack.message' OR (event_type = 'chat.message' AND filter_predicate ->> 'provider' = 'slack'))
    SQL
  end
end
