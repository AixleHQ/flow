# frozen_string_literal: true

# Everything the messaging port kept for Slack's sake now reads the one chat shape
# (docs/design/teams-integration.md §19): `slack.message` triggers and events become
# `chat.message` ones naming Slack, a run's Slack-only context becomes its chat
# origin, steps that named a slack_* tool name its chat_* successor, and
# notify_on_failure gives way to status_reporting.
class RetireLegacyChatShapes < ActiveRecord::Migration[8.1]
  TOOL_SUCCESSORS = {
    "slack_post_message" => "chat_post_message",
    "slack_update_message" => "chat_update_message",
    "slack_delete_message" => "chat_delete_message",
    "slack_read_thread" => "chat_read_thread"
  }.freeze

  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  class MigrationStep < ActiveRecord::Base
    self.table_name = "steps"
  end

  class MigrationWorkflow < ActiveRecord::Base
    self.table_name = "workflows"
  end

  def up
    execute <<~SQL.squish
      UPDATE trigger_bindings
      SET event_type = 'chat.message', filter_predicate = COALESCE(filter_predicate, '{}'::jsonb) || '{"provider": "slack"}'::jsonb,
          updated_at = NOW()
      WHERE event_type = 'slack.message'
    SQL
    execute <<~SQL.squish
      UPDATE trigger_events
      SET event_type = 'chat.message', data = COALESCE(data, '{}'::jsonb) || '{"provider": "slack"}'::jsonb
      WHERE event_type = 'slack.message'
    SQL
    move_slack_run_context
    retire_slack_tools
    execute <<~SQL.squish
      UPDATE trigger_bindings SET status_reporting = 'none', updated_at = NOW()
      WHERE notify_on_failure = FALSE AND status_reporting <> 'none'
    SQL
    remove_column :trigger_bindings, :notify_on_failure
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def move_slack_run_context
    execute <<~SQL.squish
      UPDATE workflow_runs SET shared_context = shared_context || jsonb_build_object('chat', jsonb_strip_nulls(jsonb_build_object(
        'provider', 'slack',
        'integration_id', shared_context -> 'slack' -> 'integration_id',
        'workspace_id', shared_context -> 'slack' -> 'team',
        'conversation', jsonb_strip_nulls(jsonb_build_object('id', shared_context -> 'slack' -> 'channel', 'type', 'channel')),
        'thread_id', COALESCE(shared_context -> 'slack' -> 'thread_ts', shared_context -> 'slack' -> 'ts'),
        'message_id', shared_context -> 'slack' -> 'ts',
        'actor', jsonb_strip_nulls(jsonb_build_object('id', shared_context -> 'slack' -> 'user')),
        'text', shared_context -> 'slack' -> 'text'
      )))
      WHERE shared_context ? 'slack' AND NOT shared_context ? 'chat'
    SQL
    execute "UPDATE workflow_runs SET shared_context = shared_context - 'slack' WHERE shared_context ? 'slack'"
  end

  # A code tool's row is shared by every project. Where the successor's row does
  # not exist yet, the old row is renamed in place and keeps every reference to
  # it; the reconciler then rewrites its definition. Where both exist, references
  # move to the successor and the old row is retired as the reconciler would.
  def retire_slack_tools
    TOOL_SUCCESSORS.each do |old_name, new_name|
      old_row = MigrationTool.find_by(source: "code", name: old_name, deleted_at: nil)
      next if old_row.nil?

      new_row = MigrationTool.find_by(source: "code", name: new_name, deleted_at: nil)
      if new_row.nil?
        old_row.update_columns(name: new_name, updated_at: Time.current)
        next
      end

      repoint_tool(old_row.id, new_row.id)
      old_row.update_columns(deleted_at: Time.current, enabled: false, updated_at: Time.current)
    end
  end

  def repoint_tool(from, to)
    replace = ->(ids) { ids.map { |id| id.to_i == from ? to : id.to_i }.uniq }

    MigrationStep.where("tool_ids @> ?::jsonb OR tool_ids @> ?::jsonb", [ from ].to_json, [ from.to_s ].to_json)
                 .find_each { |step| step.update_columns(tool_ids: replace.call(Array(step.tool_ids))) }
    MigrationWorkflow.where("config -> 'base_tool_ids' @> ?::jsonb OR config -> 'base_tool_ids' @> ?::jsonb",
                            [ from ].to_json, [ from.to_s ].to_json).find_each do |workflow|
      config = workflow.config.to_h
      workflow.update_columns(config: config.merge("base_tool_ids" => replace.call(Array(config["base_tool_ids"]))))
    end
  end
end
